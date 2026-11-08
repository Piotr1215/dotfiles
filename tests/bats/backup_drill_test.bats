#!/usr/bin/env bats

# Prepare an isolated home, NAS mirror, SQLite DB, and restic stub.
setup() {
  export HOME="$BATS_TEST_TMPDIR/home" BACKUP_ROOT="$BATS_TEST_TMPDIR/nas" TMPDIR="$BATS_TEST_TMPDIR"
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
  export BACKUP_FSTAB="$HOME/fstab"
  cat > "$BATS_TEST_TMPDIR/bin/restic" <<'STUB'
#!/usr/bin/env python3
import json, os, pathlib, shutil, sys
h=pathlib.Path(os.environ['HOME']); a=sys.argv[1:]
if a[0]=='snapshots':
 print(json.dumps([{'id':'test','time':'2099-01-01T00:00:00Z','paths':[str(h/'.local/share/task-backups')]}]))
elif a[0]=='ls':
 if '--recursive' in a:
  for i in range(6): print(json.dumps({'type':'file','path':str(h/f'fixture{i}'),'size':10}))
 else: print(json.dumps({'type':'file','path':str(h/'.local/share/task-backups/taskchampion.sqlite3')}))
elif a[0]=='restore':
 p=pathlib.Path(a[a.index('--include')+1]); target=pathlib.Path(a[a.index('--target')+1])/str(p).lstrip('/'); target.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(p,target)
else: sys.exit(1)
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/restic"
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

@test "task mirror rejects an excessive row difference" {
  export BACKUP_DRILL_TASK_DELTA=0
  TASK_FILE="$HOME/.task/taskchampion.sqlite3" python3 -c 'import sqlite3,os; c=sqlite3.connect(os.environ["TASK_FILE"]); c.execute("insert into tasks values(2)"); c.commit()'
  run "$DRILL_SCRIPT" --layer task
  [ "$status" -eq 1 ]
  [[ "$output" == *"row count differs"* ]]
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

@test "task mirror corrupt database fails integrity check" {
  printf 'not sqlite' > "$BACKUP_ROOT/taskwarrior-mirror/taskchampion.sqlite3"
  run "$DRILL_SCRIPT" --layer task
  [ "$status" -eq 1 ]
  jq -e '.layers.task.ok == false' "$HOME/.local/state/backup-drill/last.json"
}

@test "HTTPS layer rejects a non-200 response" {
  printf '#!/usr/bin/env bash\nprintf 503\n' > "$BATS_TEST_TMPDIR/bin/curl"
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
  run "$DRILL_SCRIPT" --layer taskchampion
  [ "$status" -eq 1 ]
  [[ "$output" == *"HTTP 503"* ]]
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
  printf 'broken' > "$BACKUP_ROOT/taskwarrior-mirror/taskchampion.sqlite3"
  run "$DRILL_SCRIPT" --layer task
  [ "$status" -eq 1 ]
  jq -e '.layers.task.ok == false and .layers.task.last_success > 0' "$HOME/.local/state/backup-drill/last.json"
}
