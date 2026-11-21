#!/usr/bin/env bats

# Prepare an isolated home, NAS mirror, SQLite DB, and restic stub.
setup() {
  local test_fd
  test_fd=$(command -v fd || true)
  export HOME="$BATS_TEST_TMPDIR/home" BACKUP_ROOT="$BATS_TEST_TMPDIR/nas" TMPDIR="$BATS_TEST_TMPDIR"
  export RESTIC_REPOSITORY="$BATS_TEST_TMPDIR/restic-repo" RESTIC_PASSWORD_FILE="$BATS_TEST_TMPDIR/restic-password"
  export BACKUP_DRILL_STATE="$HOME/.local/state/backup-drill/last.json" TASK_SNAPSHOT_PATH="$HOME/.local/share/task-backups" WIP_MIRROR_DIR=wip
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export DRILL_SCRIPT="$BATS_TEST_DIRNAME/../../scripts/__backup_drill.sh"
  mkdir -p "$HOME/.local/state" "$HOME/.local/share/task-backups" "$HOME/.task" "$HOME/dev" "$BACKUP_ROOT/home" "$BACKUP_ROOT/dev" "$BACKUP_ROOT/taskwarrior-mirror" "$BACKUP_ROOT/system-backup/etc" "$BATS_TEST_TMPDIR/bin"
  date +%s > "$HOME/.local/state/backup-last-success"
  python3 - <<'PY'
import os, pathlib, sqlite3
h=pathlib.Path(os.environ['HOME']); n=pathlib.Path(os.environ['BACKUP_ROOT'])
for d in (h, h/'dev'):
    for i in range(6):
        p=d/f'fixture{i}'; p.write_text(f'file {i}'); os.utime(p,(1,1))
        q=n/('home' if d == h else 'dev')/p.name; q.write_text(p.read_text())
db=h/'.task/taskchampion.sqlite3'
with sqlite3.connect(db) as c:
    c.execute('create table tasks(id integer)'); c.execute('insert into tasks values(1)')
for p in (n/'taskwarrior-mirror/taskchampion.sqlite3', h/'.local/share/task-backups/taskchampion.sqlite3'):
    p.write_bytes(db.read_bytes())
(n/'system-backup/etc/fstab').write_text('fstab')
(h/'fstab').write_text('fstab')
PY
  mkdir -p "$HOME/.local/state/taskwarrior/briefs" "$HOME/.local/state/gordon"
  printf 'brief' > "$HOME/.local/state/taskwarrior/briefs/one"
  printf 'state' > "$HOME/.local/state/gordon/one"
  for d in "$HOME/.local/state/taskwarrior/briefs" "$HOME/.local/state/gordon"; do
    mkdir -p "$BACKUP_ROOT/taskwarrior-mirror/state$d"
    cp "$d/one" "$BACKUP_ROOT/taskwarrior-mirror/state$d/one"
    touch -d '@1' "$d/one"
  done
  date +%s > "$BACKUP_ROOT/taskwarrior-mirror/.dirs-ok-at"
  cat > "$BATS_TEST_TMPDIR/bin/task" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == _get ]]; then
  case "$2" in
    rc.sync.server.url) printf '%s\n' 'https://example.invalid/' ;;
    rc.sync.server.client_id) printf '%s\n' 'client-private-fixture' ;;
    rc.sync.encryption_secret) if [[ ${BAD_SETTING:-0} == 1 ]]; then printf 'secret-private-fixture\377'; exit 0; fi; printf '%s\n' 'secret-private-fixture' ;;
  esac
elif [[ "$2" == sync ]]; then
  [[ "$(stat -c %a "$TASKRC")" == 600 ]] || exit 1
  [[ -d "$TASKDATA" && -z "$(ls -A "$TASKDATA")" ]] || exit 1
  [[ $(wc -l < "$TASKRC") -eq 3 ]] || exit 1
  printf '%s' secret-private-fixture >&2
  if [[ ${FAIL_SYNC:-0} == 1 ]]; then printf '%s' secret-private-fixture; exit 1; fi
elif [[ "$4" == count ]]; then
  [[ "$2" == rc.context= ]] || exit 1
  if [[ "$3" == status:pending ]]; then
    if [[ "$TASKRC" == "$TMPDIR"/* ]]; then printf '%s\n' "${RESTORED_COUNT:-8}"; else printf '%s\n' 8; fi
  else printf '2\n'; fi
else exit 1
fi
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/task"
  export BACKUP_FSTAB="$HOME/fstab"
  cat > "$BATS_TEST_TMPDIR/bin/restic" <<'STUB'
#!/usr/bin/env python3
import json, os, pathlib, shutil, sys
h=pathlib.Path(os.environ['HOME']); a=sys.argv[1:]
assert os.environ.get('RESTIC_REPOSITORY') == os.environ['BATS_TEST_TMPDIR']+'/restic-repo'
assert os.environ.get('RESTIC_PASSWORD_FILE') == os.environ['BATS_TEST_TMPDIR']+'/restic-password'
with open(os.environ['BATS_TEST_TMPDIR']+'/restic-calls','a') as f: f.write(' '.join(a)+'\n')
while a and a[0] in ('-r','--retry-lock'): a=a[2:]
if a[0]=='check': sys.exit(int(os.environ.get('RESTIC_CHECK_FAIL','0')))
if a[0]=='snapshots':
 fixture=pathlib.Path(os.environ['BATS_TEST_TMPDIR'])/'snapshots.json'
 if fixture.exists(): print(fixture.read_text(),end='')
 else: print(json.dumps([{'id':'test','time':'2099-01-01T00:00:00Z','paths':[str(h/'.local/share/task-backups')]}]))
elif a[0]=='ls':
 if '--recursive' in a:
  for i in range(6): print(json.dumps({'type':'file','path':str(h/f'fixture{i}'),'size':10}))
 else:
  fixture=pathlib.Path(os.environ['BATS_TEST_TMPDIR'])/('restic-'+a[a.index('--json')+1]+'.jsonl')
  if fixture.exists(): print(fixture.read_text(),end='')
  else: print(json.dumps({'type':'file','path':str(h/'.local/share/task-backups/taskchampion.sqlite3')}))
elif a[0]=='restore':
 p=pathlib.Path(a[a.index('--include')+1]); target=pathlib.Path(a[a.index('--target')+1])/str(p).lstrip('/'); target.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(p,target)
else: sys.exit(1)
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/restic"
  # Run fd only on the fixture home and record that the real search ran.
  if [[ -n "$test_fd" ]]; then
    export DRILL_TEST_FD="$test_fd"
    cat > "$BATS_TEST_TMPDIR/bin/fd" <<'STUB'
#!/usr/bin/env bash
[[ ${!#} == "$HOME" ]] || exit 1
printf '%s\n' "$*" > "$BATS_TEST_TMPDIR/fd-calls"
exec "$DRILL_TEST_FD" "$@"
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/fd"
  fi
  printf '#!/usr/bin/env bash\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/pgrep"
  chmod +x "$BATS_TEST_TMPDIR/bin/pgrep"
  # The drive layers: the WIP unit is not enabled and the drive job has not run unless a test says so.
  export DRIVE_MOUNT="$BATS_TEST_TMPDIR/nvme" DRIVE_UUID=fixture-uuid DRIVE_STATE_DIR="$BATS_TEST_TMPDIR/drive-state"
  export MEDIA_SOURCES="$HOME/Videos:$HOME/Downloads"
  cat > "$BATS_TEST_TMPDIR/bin/systemctl" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  is-enabled) [[ ${WIP_ENABLED:-0} == 1 ]] ;;
  is-active) [[ ${WIP_ACTIVE:-1} == 1 ]] ;;
  *) exit 1 ;;
esac
STUB
  cat > "$BATS_TEST_TMPDIR/bin/findmnt" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "${WIP_FINDMNT-fixture-uuid btrfs}"
STUB
  # Stands in for root: reads a mode 000 fixture by lending it read permission.
  cat > "$BATS_TEST_TMPDIR/bin/sudo" <<'STUB'
#!/usr/bin/env bash
[[ ${SUDO_FAIL:-0} == 1 || $1 != -n || $2 != cat || $3 != -- || $# -ne 4 ]] && exit 1
chmod u+r "$4" && cat "$4"; rc=$?; chmod u-r "$4"; exit $rc
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/systemctl" "$BATS_TEST_TMPDIR/bin/findmnt" "$BATS_TEST_TMPDIR/bin/sudo"
}

# Mirror the dev fixtures onto the fake WIP drive, with one prior version of fixture0.
wip_drive() {
  local live="$DRIVE_MOUNT/wip/live$HOME/dev" versions="$DRIVE_MOUNT/wip/versions$HOME/dev"
  mkdir -p "$live" "$versions"
  cp -p "$HOME/dev/fixture"* "$live/"
  printf 'older' > "$versions/fixture0@1700000000000000000-0123abcd"
}

# Create an old regular .envrc under the isolated home.
envrc_file() {
  mkdir -p "$(dirname "$HOME/$1")"
  printf '%s' "$2" > "$HOME/$1"
  touch -d '@946684800' "$HOME/$1"
}

# Model the explicit-path and whole-home snapshots from one nightly run.
envrc_snapshots() {
  cat > "$BATS_TEST_TMPDIR/snapshots.json" <<'JSON'
[{"id":"explicit","time":"2030-06-01T10:00:00Z","paths":[]},
 {"id":"home","time":"2030-06-01T12:00:00Z","tags":["home"]}]
JSON
}

# Model restic's JSON-lines listing, including its snapshot header.
envrc_listing() {
  local id="$1"
  shift
  python3 - "$BATS_TEST_TMPDIR/restic-$id.jsonl" "$id" "$@" <<'PY'
import json, pathlib, sys
with open(sys.argv[1], 'w') as output:
    output.write(json.dumps({'struct_type': 'snapshot', 'id': sys.argv[2]}) + '\n')
    for name in sys.argv[3:]:
        path = pathlib.Path(name)
        node = {'struct_type': 'node', 'type': 'file', 'name': path.name,
                'path': str(path), 'size': path.stat().st_size, 'mtime': '2000-01-01T00:00:00Z'}
        output.write(json.dumps(node) + '\n')
PY
}

@test "envrc coverage unions explicit and home snapshots, including ignored hidden files" {
  local hidden_path=$'.hidden/ignored\nfolder/.envrc'
  envrc_file '.envrc' root
  envrc_file 'dev/repo/.envrc' repository
  envrc_file "$hidden_path" hidden
  mkdir -p "$HOME/dev/repo/.git"
  printf '.envrc\n' > "$HOME/dev/repo/.gitignore"
  envrc_snapshots
  envrc_listing explicit "$HOME/dev/repo/.envrc"
  envrc_listing home "$HOME/.envrc" "$HOME/$hidden_path"
  run "$DRILL_SCRIPT" --layer envrc
  [ "$status" -eq 0 ]
  [[ "$output" == *"3 .envrc found; 3 in the latest run's snapshots; skipped 0 worktree, 0 third-party, 0 newer than the run"* ]]
  jq -e '.layers.envrc.ok == true and .layers.envrc.last_success > 0' "$HOME/.local/state/backup-drill/last.json"
  if [[ -n ${DRILL_TEST_FD:-} ]]; then
    [[ "$(cat "$BATS_TEST_TMPDIR/fd-calls")" == *'-H -I -t f -g .envrc'* ]]
  fi
  grep -Fx 'snapshots --no-lock --json' "$BATS_TEST_TMPDIR/restic-calls"
  grep -Fx 'ls --no-lock --json explicit' "$BATS_TEST_TMPDIR/restic-calls"
  grep -Fx 'ls --no-lock --json home' "$BATS_TEST_TMPDIR/restic-calls"
}

@test "a missing old envrc fails, names it, and records the failure" {
  envrc_file 'dev/missing/.envrc' missing
  envrc_snapshots
  envrc_listing explicit
  envrc_listing home
  run "$DRILL_SCRIPT" --layer envrc
  [ "$status" -eq 1 ]
  [[ "$output" == *"1 .envrc missing"* && "$output" == *"$HOME/dev/missing/.envrc"* ]]
  jq -e '.layers.envrc.ok == false and (.layers.envrc.detail | contains("dev/missing/.envrc"))' "$HOME/.local/state/backup-drill/last.json"
}

@test "missing envrc output shows the total and at most ten paths" {
  for i in {00..11}; do envrc_file "dev/repo$i/.envrc" missing; done
  envrc_snapshots
  envrc_listing explicit
  envrc_listing home
  run "$DRILL_SCRIPT" --layer envrc
  [ "$status" -eq 1 ]
  [[ "$output" == *"12 .envrc missing"* && "$output" == *"$HOME/dev/repo09/.envrc"* ]]
  [[ "$output" != *"$HOME/dev/repo10/.envrc"* && "$output" != *"$HOME/dev/repo11/.envrc"* ]]
}

@test "worktrees and third-party copies are counted and skipped" {
  envrc_file '.task-worktrees/task/.envrc' skipped
  envrc_file 'dev/repo-worktrees/branch/.envrc' skipped
  envrc_file 'dev/repo/node_modules/pkg/.envrc' skipped
  envrc_file 'dev/repo/vendor/pkg/.envrc' skipped
  envrc_file '.cache/pkg/.envrc' skipped
  envrc_file '.cargo/registry/src/pkg/.envrc' skipped
  envrc_file 'go/pkg/mod/pkg/.envrc' skipped
  envrc_snapshots
  envrc_listing explicit
  envrc_listing home
  run "$DRILL_SCRIPT" --layer envrc
  [ "$status" -eq 0 ]
  [[ "$output" == *"7 .envrc found; 0 in the latest run's snapshots; skipped 2 worktree, 5 third-party, 0 newer than the run"* ]]
}

@test "files at or after the earliest selected snapshot are skipped" {
  envrc_file 'dev/at-start/.envrc' at-start
  envrc_file 'dev/after-start/.envrc' after-start
  touch -d '2030-06-01T10:00:00Z' "$HOME/dev/at-start/.envrc"
  touch -d '2030-06-01T11:00:00Z' "$HOME/dev/after-start/.envrc"
  envrc_snapshots
  envrc_listing explicit
  envrc_listing home
  run "$DRILL_SCRIPT" --layer envrc
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 .envrc found; 0 in the latest run's snapshots; skipped 0 worktree, 0 third-party, 2 newer than the run"* ]]
}

@test "an old envrc with a size mismatch fails" {
  envrc_file 'dev/repo/.envrc' snapshot
  envrc_snapshots
  envrc_listing explicit "$HOME/dev/repo/.envrc"
  envrc_listing home
  printf 'different size' > "$HOME/dev/repo/.envrc"
  touch -d '@946684800' "$HOME/dev/repo/.envrc"
  run "$DRILL_SCRIPT" --layer envrc
  [ "$status" -eq 1 ]
  [[ "$output" == *"size"* && "$output" == *"$HOME/dev/repo/.envrc"* ]]
  jq -e '.layers.envrc.ok == false' "$HOME/.local/state/backup-drill/last.json"
}

@test "the newest selected copy supplies metadata for a path in multiple snapshots" {
  envrc_file 'dev/repo/.envrc' old
  envrc_snapshots
  envrc_listing explicit "$HOME/dev/repo/.envrc"
  printf 'newer copy' > "$HOME/dev/repo/.envrc"
  touch -d '@946684800' "$HOME/dev/repo/.envrc"
  envrc_listing home "$HOME/dev/repo/.envrc"
  run "$DRILL_SCRIPT" --layer envrc
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 .envrc found; 1 in the latest run's snapshots"* ]]
}

@test "browser and old snapshots are excluded but the six-hour boundary is included" {
  envrc_file 'dev/browser-only/.envrc' browser
  envrc_file 'dev/old-only/.envrc' old
  envrc_file 'dev/boundary/.envrc' boundary
  cat > "$BATS_TEST_TMPDIR/snapshots.json" <<'JSON'
[{"id":"old","time":"2030-06-01T05:59:59Z"},
 {"id":"boundary","time":"2030-06-01T08:00:00+02:00"},
 {"id":"home","time":"2030-06-01T11:30:00Z","tags":["home"]},
 {"id":"browser","time":"2030-06-01T12:00:00Z","tags":["browser"]}]
JSON
  envrc_listing old "$HOME/dev/old-only/.envrc"
  envrc_listing boundary "$HOME/dev/boundary/.envrc"
  envrc_listing home
  envrc_listing browser "$HOME/dev/browser-only/.envrc"
  run "$DRILL_SCRIPT" --layer envrc
  [ "$status" -eq 1 ]
  [[ "$output" == *"2 .envrc missing"* && "$output" == *"$HOME/dev/old-only/.envrc"* && "$output" == *"$HOME/dev/browser-only/.envrc"* ]]
  [[ "$output" != *"$HOME/dev/boundary/.envrc"* ]]
  grep -Fx 'ls --no-lock --json boundary' "$BATS_TEST_TMPDIR/restic-calls"
  grep -Fx 'ls --no-lock --json home' "$BATS_TEST_TMPDIR/restic-calls"
  ! grep -E '^ls .* (old|browser)$' "$BATS_TEST_TMPDIR/restic-calls"
}

@test "no snapshots fails" {
  printf '[]\n' > "$BATS_TEST_TMPDIR/snapshots.json"
  run "$DRILL_SCRIPT" --layer envrc
  [ "$status" -eq 1 ]
  [[ "$output" == *"no snapshots"* ]]
  jq -e '.layers.envrc.ok == false' "$HOME/.local/state/backup-drill/last.json"
}

@test "a latest window with only browser snapshots fails" {
  printf '[{"id":"browser","time":"2030-06-01T12:00:00Z","tags":["browser"]}]\n' > "$BATS_TEST_TMPDIR/snapshots.json"
  run "$DRILL_SCRIPT" --layer envrc
  [ "$status" -eq 1 ]
  [[ "$output" == *"no non-browser snapshots"* ]]
}

@test "envrc search does not follow file or directory symlinks" {
  mkdir -p "$BATS_TEST_TMPDIR/outside" "$HOME/symlink"
  printf outside > "$BATS_TEST_TMPDIR/outside/.envrc"
  ln -s "$BATS_TEST_TMPDIR/outside/.envrc" "$HOME/symlink/.envrc"
  ln -s "$BATS_TEST_TMPDIR/outside" "$HOME/link-dir"
  envrc_snapshots
  envrc_listing explicit
  envrc_listing home
  run "$DRILL_SCRIPT" --layer envrc
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 .envrc found"* ]]
}

@test "envrc search falls back to os.walk when fd is unavailable" {
  local path=$'dev/odd\nname/.envrc' tool
  envrc_file "$path" data
  mkdir -p "$BATS_TEST_TMPDIR/outside" "$HOME/symlink"
  printf outside > "$BATS_TEST_TMPDIR/outside/.envrc"
  ln -s "$BATS_TEST_TMPDIR/outside/.envrc" "$HOME/symlink/.envrc"
  ln -s "$BATS_TEST_TMPDIR/outside" "$HOME/link-dir"
  envrc_snapshots
  envrc_listing explicit "$HOME/$path"
  envrc_listing home
  mkdir -p "$BATS_TEST_TMPDIR/nofd"
  for tool in bash python3 mktemp; do ln -s "$(command -v "$tool")" "$BATS_TEST_TMPDIR/nofd/$tool"; done
  ln -s /usr/bin/rm "$BATS_TEST_TMPDIR/nofd/rm"
  ln -s "$BATS_TEST_TMPDIR/bin/restic" "$BATS_TEST_TMPDIR/nofd/restic"
  PATH="$BATS_TEST_TMPDIR/nofd" run "$DRILL_SCRIPT" --layer envrc
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 .envrc found; 1 in the latest run's snapshots"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/fd-calls" ]
}

@test "a plain drill fails for missing envrc coverage without adding a status row" {
  envrc_file 'dev/missing/.envrc' missing
  run "$DRILL_SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"envrc: FAIL:"* && "$output" == *"$HOME/dev/missing/.envrc"* ]]
  jq -e '.layers.envrc.ok == false and .layers.restic.ok == true' "$HOME/.local/state/backup-drill/last.json"
  run "$BATS_TEST_DIRNAME/../../scripts/__backup_status.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"envrc"* ]]
}

@test "restic restores a database and three files into scratch" {
  run "$DRILL_SCRIPT" --layer restic
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 rows; 3 restored files match"* ]]
  jq -e '.layers.restic.ok == true' "$HOME/.local/state/backup-drill/last.json"
}

@test "mirror drill compares five restored files and records a mismatch" {
  run "$DRILL_SCRIPT" --layer home
  [ "$status" -eq 0 ]
  for f in "$BACKUP_ROOT/home/fixture"*; do printf 'broken' > "$f"; done
  run "$DRILL_SCRIPT" --layer home
  [ "$status" -eq 1 ]
  [[ "$output" == *"differs"* ]]
  jq -e '.layers.home.ok == false' "$HOME/.local/state/backup-drill/last.json"
}

@test "task state mirror checks both retained directories" {
  run "$DRILL_SCRIPT" --layer task
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 state files match"* ]]
  printf 'broken' > "$BACKUP_ROOT/taskwarrior-mirror/state$HOME/.local/state/gordon/one"
  run "$DRILL_SCRIPT" --layer task
  [ "$status" -eq 1 ]
  [[ "$output" == *"mirror differs"* ]]
}

@test "task state mirror ignores files newer than the successful mirror" {
  printf 'changed' > "$HOME/.local/state/gordon/one"
  touch -d 'next hour' "$HOME/.local/state/gordon/one"
  printf 'new' > "$HOME/.local/state/taskwarrior/briefs/new"
  touch -d 'next hour' "$HOME/.local/state/taskwarrior/briefs/new"
  run "$DRILL_SCRIPT" --layer task
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 state files match"* ]]
}

@test "system copy mismatch fails and partial runs retain other results" {
  run "$DRILL_SCRIPT" --layer task
  [ "$status" -eq 0 ]
  printf 'changed' > "$BACKUP_ROOT/system-backup/etc/fstab"
  run "$DRILL_SCRIPT" --layer system
  [ "$status" -eq 1 ]
  jq -e '.layers.task.ok == true and .layers.system.ok == false' "$HOME/.local/state/backup-drill/last.json"
}

@test "invalid layer exits without a result" {
  run "$DRILL_SCRIPT" --layer bogus
  [ "$status" -eq 2 ]
  [ ! -e "$HOME/.local/state/backup-drill/last.json" ]
}

@test "TaskChampion restores tasks with private settings and cleans scratch" {
  run "$DRILL_SCRIPT" --layer taskchampion
  [ "$status" -eq 0 ]
  [[ "$output" == *"restored 10 tasks from the server, live 10"* ]]
  [[ "$output" != *private-fixture* ]]
  ! rg -q 'secret-private-fixture|client-private-fixture' "$HOME/.local/state/backup-drill"
  [ -z "$(find "$TMPDIR" -name taskrc -print)" ]
}

@test "TaskChampion count overrides an active context for live and scratch databases" {
  export TASK_CONTEXT=work
  run "$DRILL_SCRIPT" --layer taskchampion
  [ "$status" -eq 0 ]
  [[ "$output" == *"restored 10 tasks from the server, live 10"* ]]
}

@test "TaskChampion rejects a count mismatch without exposing secrets" {
  export RESTORED_COUNT=20 BACKUP_DRILL_TASK_DELTA=0
  run "$DRILL_SCRIPT" --layer taskchampion
  [ "$status" -eq 1 ]
  [[ "$output" == *"task count differs"* ]]
  [[ "$output" != *private-fixture* ]]
  ! rg -q 'secret-private-fixture|client-private-fixture' "$HOME/.local/state/backup-drill"
}

@test "malformed sync setting does not expose its bytes" {
  export BAD_SETTING=1
  run "$DRILL_SCRIPT" --layer taskchampion
  [ "$status" -eq 1 ]
  [[ "$output" != *secret-private-fixture* ]]
  ! rg -q 'secret-private-fixture|client-private-fixture' "$HOME/.local/state/backup-drill"
}

@test "failed sync does not expose task diagnostics in output or state" {
  export FAIL_SYNC=1
  run "$DRILL_SCRIPT" --layer taskchampion
  [ "$status" -eq 1 ]
  [[ "$output" != *secret-private-fixture* ]]
  ! rg -q 'secret-private-fixture|client-private-fixture' "$HOME/.local/state/backup-drill"
}

@test "restic failure is recorded without leaking its diagnostics" {
  printf '#!/usr/bin/env bash\necho sensitive-diagnostic >&2\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/restic"
  chmod +x "$BATS_TEST_TMPDIR/bin/restic"
  run "$DRILL_SCRIPT" --layer restic
  [ "$status" -eq 1 ]
  [[ "$output" != *sensitive-diagnostic* ]]
  jq -e '.layers.restic.ok == false' "$HOME/.local/state/backup-drill/last.json"
}

@test "home sampling skips the separately generated settings dump" {
  printf 'live\n' > "$HOME/pop_os_settings_backup.ini"
  printf 'generated dump\n' > "$BACKUP_ROOT/home/pop_os_settings_backup.ini"
  touch -d '@1' "$HOME/pop_os_settings_backup.ini"
  touch -d 'next year' "$HOME/fixture5"
  run "$DRILL_SCRIPT" --layer home
  [ "$status" -eq 0 ]
}

@test "a failed partial drill preserves its last successful timestamp" {
  run "$DRILL_SCRIPT" --layer task
  [ "$status" -eq 0 ]
  printf 'broken' > "$BACKUP_ROOT/taskwarrior-mirror/state$HOME/.local/state/gordon/one"
  run "$DRILL_SCRIPT" --layer task
  [ "$status" -eq 1 ]
  jq -e '.layers.task.ok == false and .layers.task.last_success > 0' "$HOME/.local/state/backup-drill/last.json"
}

@test "wip layer is skipped and unrecorded before the unit is enabled" {
  mkdir -p "$HOME/.local/state/backup-drill"
  printf '{"last_run":7,"layers":{"wip":{"ok":true,"last_run":1,"last_success":1}}}' > "$HOME/.local/state/backup-drill/last.json"
  run "$DRILL_SCRIPT" --layer wip
  [ "$status" -eq 0 ]
  [[ "$output" == *"wip: skipped: wip-mirror.service not enabled"* ]]
  jq -e '(.layers | has("wip") | not) and .last_run == 7' "$HOME/.local/state/backup-drill/last.json"
  run "$DRILL_SCRIPT"
  [ "$status" -eq 0 ]
  jq -e '(.layers | has("wip") | not) and .layers.restic.ok == true' "$HOME/.local/state/backup-drill/last.json"
}

@test "an enabled unit without the expected drive fails the drill" {
  export WIP_ENABLED=1
  wip_drive
  WIP_FINDMNT='other-uuid btrfs' run "$DRILL_SCRIPT" --layer wip
  [ "$status" -eq 1 ]
  [[ "$output" == *"expected UUID"* ]]
  jq -e '.layers.wip.ok == false' "$HOME/.local/state/backup-drill/last.json"
  WIP_FINDMNT='' run "$DRILL_SCRIPT" --layer wip
  [ "$status" -eq 1 ]
  [[ "$output" == *"expected UUID"* ]]
}

@test "an enabled drive without both trees fails the drill" {
  export WIP_ENABLED=1
  mkdir -p "$DRIVE_MOUNT/wip/live"
  run "$DRILL_SCRIPT" --layer wip
  [ "$status" -eq 1 ]
  [[ "$output" == *"live or versions directory missing"* ]]
}

@test "wip drill restores live copies and a prior version into scratch" {
  export WIP_ENABLED=1
  wip_drive
  run "$DRILL_SCRIPT" --layer wip
  [ "$status" -eq 0 ]
  [[ "$output" == *"5 restored live files match; 1 prior versions restore intact; 0 root-only copies read with sudo"* ]]
  jq -e '.layers.wip.ok == true and .layers.wip.last_success > 0' "$HOME/.local/state/backup-drill/last.json"
}

@test "a live copy that differs from its source fails" {
  export WIP_ENABLED=1
  wip_drive
  for f in "$DRIVE_MOUNT/wip/live$HOME/dev/fixture"*; do printf 'broken' > "$f"; touch -d '@1' "$f"; done
  run "$DRILL_SCRIPT" --layer wip
  [ "$status" -eq 1 ]
  [[ "$output" == *"differs"* ]]
}

@test "root-only copies are restored with sudo and compared" {
  export WIP_ENABLED=1
  wip_drive
  chmod 000 "$DRIVE_MOUNT/wip/live$HOME/dev/fixture"* "$DRIVE_MOUNT/wip/versions$HOME/dev/fixture0@"*
  run "$DRILL_SCRIPT" --layer wip
  [ "$status" -eq 0 ]
  [[ "$output" == *"5 restored live files match; 1 prior versions restore intact; 6 root-only copies read with sudo"* ]]
  for f in "$DRIVE_MOUNT/wip/live$HOME/dev/fixture"*; do chmod 600 "$f"; printf 'broken' > "$f"; touch -d '@1' "$f"; chmod 000 "$f"; done
  run "$DRILL_SCRIPT" --layer wip
  [ "$status" -eq 1 ]
  [[ "$output" == *"differs"* ]]
}

@test "a sudo refusal fails the drill instead of skipping private copies" {
  export WIP_ENABLED=1 SUDO_FAIL=1
  wip_drive
  chmod 000 "$DRIVE_MOUNT/wip/live$HOME/dev/fixture"*
  run "$DRILL_SCRIPT" --layer wip
  [ "$status" -eq 1 ]
  [[ "$output" == *"sudo -n could not read a root-only copy"* ]]
}

@test "a prior version without a current copy on the drive fails" {
  export WIP_ENABLED=1
  wip_drive
  rm "$DRIVE_MOUNT/wip/live$HOME/dev/fixture0"
  run "$DRILL_SCRIPT" --layer wip
  [ "$status" -eq 1 ]
  [[ "$output" == *"no current copy"* ]]
}

@test "a drive with no prior versions yet passes" {
  export WIP_ENABLED=1
  wip_drive
  rm "$DRIVE_MOUNT/wip/versions$HOME/dev/fixture0@"*
  run "$DRILL_SCRIPT" --layer wip
  [ "$status" -eq 0 ]
  [[ "$output" == *"no prior versions yet"* ]]
}

# Mirror two media folders onto the fake drive and stamp a successful drive run.
media_drive() {
  mkdir -p "$DRIVE_STATE_DIR" "$HOME/Videos" "$HOME/Downloads" "$DRIVE_MOUNT/media"
  for i in 0 1 2; do
    printf 'clip %s' "$i" > "$HOME/Videos/v$i"; printf 'doc %s' "$i" > "$HOME/Downloads/d$i"
    touch -d '@1' "$HOME/Videos/v$i" "$HOME/Downloads/d$i"
  done
  cp -rp "$HOME/Videos" "$HOME/Downloads" "$DRIVE_MOUNT/media/"
  date +%s > "$DRIVE_STATE_DIR/last-success"
}

@test "drive layers are skipped and unrecorded before the drive job succeeds" {
  run "$DRILL_SCRIPT" --layer media
  [ "$status" -eq 0 ]
  [[ "$output" == *"media: skipped: the drive job has not succeeded yet"* ]]
  run "$DRILL_SCRIPT" --layer drive-restic
  [ "$status" -eq 0 ]
  [[ "$output" == *"drive-restic: skipped"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/restic-calls" ]
}

@test "media drill restores mirrored files and catches a bad copy" {
  media_drive
  run "$DRILL_SCRIPT" --layer media
  [ "$status" -eq 0 ]
  [[ "$output" == *"5 restored media files match"* ]]
  for f in "$DRIVE_MOUNT"/media/*/*; do printf 'broken' > "$f"; done
  run "$DRILL_SCRIPT" --layer media
  [ "$status" -eq 1 ]
  [[ "$output" == *"differs"* ]]
  jq -e '.layers.media.ok == false' "$HOME/.local/state/backup-drill/last.json"
}

@test "drive layers fail when the drive is gone after the job has run" {
  media_drive
  WIP_FINDMNT='' run "$DRILL_SCRIPT" --layer media
  [ "$status" -eq 1 ]
  [[ "$output" == *"expected UUID"* ]]
  WIP_FINDMNT='' run "$DRILL_SCRIPT" --layer drive-restic
  [ "$status" -eq 1 ]
  [[ "$output" == *"expected UUID"* ]]
}

@test "drive restic drill checks and restores from the drive repo, not the NAS" {
  media_drive
  run "$DRILL_SCRIPT" --layer drive-restic
  [ "$status" -eq 0 ]
  [[ "$output" == *"check of 5% of data ok; task DB integrity ok"* ]]
  grep -Fx -- "-r $DRIVE_MOUNT/restic/secure-store --retry-lock 5m check --read-data-subset=5%" "$BATS_TEST_TMPDIR/restic-calls"
  ! grep -v -- "^-r $DRIVE_MOUNT/restic/secure-store " "$BATS_TEST_TMPDIR/restic-calls"
  RESTIC_CHECK_FAIL=1 run "$DRILL_SCRIPT" --layer drive-restic
  [ "$status" -eq 1 ]
  jq -e '.layers["drive-restic"].ok == false' "$HOME/.local/state/backup-drill/last.json"
}

@test "a keep-tagged one-off hours after the nightly does not move the window" {
  envrc_file 'dev/repo/.envrc' run
  cat > "$BATS_TEST_TMPDIR/snapshots.json" <<'JSON'
[{"id":"run","time":"2030-06-01T10:00:00Z"},
 {"id":"oneoff","time":"2030-06-01T20:00:00Z","tags":["keep","nomad-state-2030-06-01"]}]
JSON
  envrc_listing run "$HOME/dev/repo/.envrc"
  envrc_listing oneoff
  run "$DRILL_SCRIPT" --layer envrc
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 .envrc found; 1 in the latest run's snapshots"* ]]
  run grep -F 'ls --no-lock --json oneoff' "$BATS_TEST_TMPDIR/restic-calls"
  [ "$status" -eq 1 ]
}
