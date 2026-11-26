#!/usr/bin/env bats

setup_file() { bats_require_minimum_version 1.5.0; }
setup() {
  # The worktree helper lives in the private ~/.claude repo; resolve it before
  # HOME moves into the sandbox.
  WORKTREE_LIB="$HOME/.claude/scripts/__lib_worktree_base.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  export WIP_CAPTURE_TARGET="$BATS_TEST_TMPDIR/target"
  export WIP_CAPTURE_STATE="$BATS_TEST_TMPDIR/state"
  export WIP_CAPTURE_ALLOW_DIRECTORY=1
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/__wip_capture.sh"
  ROOT="$HOME/dev"
  REPO="$ROOT/project"
  MIRROR="$WIP_CAPTURE_TARGET/dev/project/.git"
  mkdir -p "$REPO" "$WIP_CAPTURE_TARGET"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.name Test
  git -C "$REPO" config user.email test@example.invalid
  printf 'base\n' > "$REPO/tracked"
  printf 'ignored\n' > "$REPO/.gitignore"
  git -C "$REPO" add .
  git -C "$REPO" commit -qm initial
}
capture() { "$SCRIPT" "$ROOT"; }

# Count sandbox attempts and let the host change a fixture while git add waits.
capture_attempt_fixture() {
  export WIP_TEST_REAL_BWRAP WIP_TEST_REAL_GIT WIP_TEST_REPO WIP_TEST_LOCK
  WIP_TEST_REAL_BWRAP=$(command -v bwrap)
  WIP_TEST_REAL_GIT=$(command -v git)
  WIP_TEST_REPO=$REPO
  WIP_TEST_LOCK="$WIP_CAPTURE_STATE/$(printf '%s' "$MIRROR" | sha256sum | cut -d ' ' -f 1).mirror.lock"
  mkdir -p "$BATS_TEST_TMPDIR/bin" "$WIP_CAPTURE_STATE"
  cat > "$BATS_TEST_TMPDIR/bin/bwrap" <<'BWRAP'
#!/usr/bin/env bash
attempt=1
if [[ -f $WIP_CAPTURE_STATE/attempts ]]; then
  attempt=$(( $(wc -l < "$WIP_CAPTURE_STATE/attempts") + 1 ))
fi
printf '%s\n' "$attempt" >> "$WIP_CAPTURE_STATE/attempts"
if flock -n "$WIP_TEST_LOCK" -c :; then
  printf 'mirror lock was not held\n' >&2
  exit 1
fi
case ${WIP_TEST_RESULT:-} in
  killed)
    printf 'repository changed during capture\n' >&2
    exit 137 ;;
  retry-failure | retry-killed)
    if (( attempt == 2 )); then
      printf 'second attempt failed\n' >&2
      [[ $WIP_TEST_RESULT == retry-failure ]] && exit 1
      exit 137
    fi ;;
  target-gone-first | target-gone-retry)
    if [[ $WIP_TEST_RESULT == target-gone-first || $attempt == 2 ]]; then
      rm -f -- "$WIP_CAPTURE_TARGET/.wip-probe"
      chmod 500 "$WIP_CAPTURE_TARGET"
      printf 'repository changed during capture\n' >&2
    else
      printf 'repository changed during capture\n' >&2
    fi
    exit 1 ;;
esac
export WIP_TEST_ATTEMPT=$attempt
if (( attempt <= ${WIP_TEST_CHANGE_ATTEMPTS:-0} )); then
  (
    for (( i=0; i<1000; i++ )); do
      if [[ -e $WIP_CAPTURE_STATE/change-request.$attempt ]]; then
        printf 'changed during attempt %s\n' "$attempt" >> "$WIP_TEST_REPO/tracked"
        : > "$WIP_CAPTURE_STATE/change-done.$attempt"
        exit 0
      fi
      sleep 0.01
    done
    exit 1
  ) &
fi
if [[ ${WIP_TEST_FIRST_NOISE:-0} == 1 && $attempt == 1 ]]; then
  printf 'captured first attempt only\n'
  printf 'skip large untracked file: first attempt only\n' >&2
fi
exec "$WIP_TEST_REAL_BWRAP" "$@"
BWRAP
  cat > "$BATS_TEST_TMPDIR/bin/git" <<'GIT'
#!/usr/bin/env bash
if [[ ${WIP_CAPTURE_SANDBOXED:-0} == 1 && ${1:-} == -c && ${2:-} == core.hooksPath=/dev/null && ${5:-} == add ]] &&
   (( ${WIP_TEST_ATTEMPT:-0} <= ${WIP_TEST_CHANGE_ATTEMPTS:-0} )); then
  : > "$WIP_CAPTURE_STATE/change-request.$WIP_TEST_ATTEMPT"
  for (( i=0; i<1000; i++ )); do
    [[ -e $WIP_CAPTURE_STATE/change-done.$WIP_TEST_ATTEMPT ]] && break
    sleep 0.01
  done
  [[ -e $WIP_CAPTURE_STATE/change-done.$WIP_TEST_ATTEMPT ]] || exit 1
fi
exec "$WIP_TEST_REAL_GIT" "$@"
GIT
  chmod +x "$BATS_TEST_TMPDIR/bin/bwrap" "$BATS_TEST_TMPDIR/bin/git"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "retries a changed repository and records the successful capture" {
  capture_attempt_fixture
  export WIP_TEST_CHANGE_ATTEMPTS=1 WIP_TEST_FIRST_NOISE=1 WIP_CAPTURE_NOW=123456
  printf '%s\t%s\n' "$REPO" 100 > "$WIP_CAPTURE_STATE/last-good.tsv"
  run capture
  [ "$status" -eq 0 ]
  [[ $output == *"captured $REPO"* ]]
  [[ $output == *'captured=1'* ]]
  [[ $output != *'first attempt only'* ]]
  [ "$(wc -l < "$WIP_CAPTURE_STATE/attempts")" -eq 2 ]
  [ "$(mirror_show main tracked)" = "$(printf 'base\nchanged during attempt 1')" ]
  [ "$(cat "$WIP_CAPTURE_STATE/last-good.tsv")" = "$(printf '%s\t123456' "$REPO")" ]
}

@test "a repository changed on both attempts warns after exactly two captures" {
  capture_attempt_fixture
  export WIP_TEST_CHANGE_ATTEMPTS=2
  run capture
  [ "$status" -eq 0 ]
  [[ $output == *"warning $REPO: changed during capture, retried next run"* ]]
  [[ $output == *'known_broken=1 failures=0'* ]]
  [ "$(wc -l < "$WIP_CAPTURE_STATE/attempts")" -eq 2 ]
  [ "$(cat "$REPO/tracked")" = "$(printf 'base\nchanged during attempt 1\nchanged during attempt 2')" ]
  [ "$(cat "$WIP_CAPTURE_STATE/known-broken.tsv")" = "$(printf '%s\tchanged during capture, retried next run' "$REPO")" ]
}

@test "a timed out capture is not retried even if its stderr mentions a change" {
  capture_attempt_fixture
  export WIP_CAPTURE_REPO_TIMEOUT=1
  git -C "$REPO" config filter.slow.clean 'printf "repository changed during capture\n" >&2; sleep 5; cat'
  printf 'tracked filter=slow\n' > "$REPO/.gitattributes"
  printf 'changed\n' > "$REPO/tracked"
  run capture
  [ "$status" -eq 0 ]
  [[ $output == *"warning $REPO: capture timed out"* ]]
  [ "$(wc -l < "$WIP_CAPTURE_STATE/attempts")" -eq 1 ]
}

@test "a killed capture is not retried even if its stderr mentions a change" {
  capture_attempt_fixture
  export WIP_TEST_RESULT=killed
  run capture
  [ "$status" -eq 0 ]
  [[ $output == *"warning $REPO: capture timed out"* ]]
  [ "$(wc -l < "$WIP_CAPTURE_STATE/attempts")" -eq 1 ]
}

@test "another capture failure is not retried" {
  capture_attempt_fixture
  mkdir -p "$WIP_CAPTURE_TARGET/dev"
  printf 'not a directory\n' > "$WIP_CAPTURE_TARGET/dev/project"
  run capture
  [ "$status" -ne 0 ]
  [[ $output == *"failed $REPO"* ]]
  [[ $output == *'failures=1'* ]]
  [ "$(wc -l < "$WIP_CAPTURE_STATE/attempts")" -eq 1 ]
}

@test "a different failure on retry is classified from the second attempt" {
  capture_attempt_fixture
  export WIP_TEST_CHANGE_ATTEMPTS=1 WIP_TEST_RESULT=retry-failure
  run capture
  [ "$status" -ne 0 ]
  [[ $output == *"failed $REPO"* ]]
  [[ $output == *'second attempt failed'* ]]
  [[ $output != *'warning '* ]]
  [ "$(wc -l < "$WIP_CAPTURE_STATE/attempts")" -eq 2 ]
}

@test "a killed retry is classified as a timeout" {
  capture_attempt_fixture
  export WIP_TEST_CHANGE_ATTEMPTS=1 WIP_TEST_RESULT=retry-killed
  run capture
  [ "$status" -eq 0 ]
  [[ $output == *"warning $REPO: capture timed out"* ]]
  [ "$(wc -l < "$WIP_CAPTURE_STATE/attempts")" -eq 2 ]
}

@test "a target that stops taking writes on the first attempt is not retried" {
  capture_attempt_fixture
  export WIP_TEST_RESULT=target-gone-first
  run capture
  chmod 700 "$WIP_CAPTURE_TARGET"
  [ "$status" -eq 75 ]
  [[ $output == *'stopped taking writes mid-run'* ]]
  [ "$(wc -l < "$WIP_CAPTURE_STATE/attempts")" -eq 1 ]
}

@test "a target that stops taking writes on retry skips the run" {
  capture_attempt_fixture
  export WIP_TEST_RESULT=target-gone-retry
  run capture
  chmod 700 "$WIP_CAPTURE_TARGET"
  [ "$status" -eq 75 ]
  [[ $output == *'stopped taking writes mid-run'* ]]
  [ "$(wc -l < "$WIP_CAPTURE_STATE/attempts")" -eq 2 ]
}

@test "mirror lock wait does not consume the capture timeout" {
  export WIP_CAPTURE_REPO_TIMEOUT=1
  mkdir -p "$WIP_CAPTURE_STATE"
  local lock="$WIP_CAPTURE_STATE/$(printf '%s' "$MIRROR" | sha256sum | cut -d ' ' -f 1).mirror.lock"
  flock "$lock" sh -c 'touch "$1"; sleep 2' sh "$BATS_TEST_TMPDIR/locked" &
  local holder=$!
  while [[ ! -e $BATS_TEST_TMPDIR/locked ]]; do sleep 0.05; done
  run capture
  wait "$holder"
  [ "$status" -eq 0 ]
  [[ $output == *"captured $REPO"* ]]
  [ -n "$(git --git-dir="$MIRROR" rev-parse refs/wip/main)" ]
}
@test "excludes marketplace clones but captures other claude repositories" {
  mkdir -p "$HOME/.claude/plugins/marketplaces"
  git clone -q "$REPO" "$HOME/.claude/plugins/marketplaces/vendor"
  git clone -q "$REPO" "$HOME/.claude/other"
  run "$SCRIPT" "$HOME/.claude"
  [ "$status" -eq 0 ]
  [[ $output == *'repositories=1 '* ]]
  [ ! -e "$WIP_CAPTURE_TARGET/.claude/plugins/marketplaces/vendor/.git" ]
  [ -d "$WIP_CAPTURE_TARGET/.claude/other/.git" ]
}
# Loads worktree_add_fresh, or skips where the private repo is absent (CI).
use_worktree_lib() {
  [[ -r $WORKTREE_LIB ]] || skip "needs ~/.claude/scripts from the private repo"
  # shellcheck source=/dev/null
  source "$WORKTREE_LIB"
}
mirror_show() { git --git-dir="$MIRROR" show "refs/wip/$1:$2"; }
linked_fixture() { git -C "$REPO" worktree add -q -b feature "$ROOT/linked"; }

# Keep an unchanged blob absent from the checkout and object database.
blobless_fixture() {
  mkdir -p "$REPO/visible"
  printf 'missing blob\n' > "$REPO/missing"
  printf 'original\n' > "$REPO/visible/file"
  git -C "$REPO" add .
  git -C "$REPO" commit -qm 'add sparse files'
  git -C "$REPO" config uploadpack.allowFilter true
  git clone -q --filter=blob:none --no-checkout "file://$REPO" "$ROOT/blobless"
  git -C "$ROOT/blobless" sparse-checkout init --no-cone
  git -C "$ROOT/blobless" sparse-checkout set --no-cone '/visible/' '/.gitignore'
  git -C "$ROOT/blobless" checkout -q
  local oid
  oid=$(git -C "$REPO" rev-parse HEAD:missing)
  git -C "$ROOT/blobless" rev-list --objects --missing=print HEAD | grep -qx "?$oid"
  printf '100644 %s\tmissing\n' "$oid" | git -C "$ROOT/blobless" update-index --index-info
  git -C "$ROOT/blobless" update-index --skip-worktree missing
  git -C "$ROOT/blobless" remote set-url origin "$BATS_TEST_TMPDIR/unavailable.git"
  [ -z "$(git -C "$ROOT/blobless" status --porcelain)" ]
}

@test "captures a clean blobless sparse clone without fetching absent blobs" {
  blobless_fixture
  run capture
  [ "$status" -eq 0 ]
  [[ $output != *"warning $ROOT/blobless"* ]]
  [ -n "$(git --git-dir="$WIP_CAPTURE_TARGET/dev/blobless/.git" rev-parse refs/wip/main)" ]
  git --git-dir="$WIP_CAPTURE_TARGET/dev/blobless/.git" rev-list --objects --missing=print refs/wip/main | grep -q '^?'
}

@test "captures a dirty blobless sparse clone without fetching absent blobs" {
  blobless_fixture
  printf 'changed offline\n' > "$ROOT/blobless/visible/file"
  run capture
  [ "$status" -eq 0 ]
  [[ $output != *"warning $ROOT/blobless"* ]]
  [ "$(git --git-dir="$WIP_CAPTURE_TARGET/dev/blobless/.git" show refs/wip/main:visible/file)" = 'changed offline' ]
  git --git-dir="$WIP_CAPTURE_TARGET/dev/blobless/.git" rev-list --objects --missing=print refs/wip/main | grep -q '^?'
}

@test "captures staged, unstaged and untracked files while excluding secrets and ignored files" {
  printf 'staged\n' > "$REPO/staged"
  git -C "$REPO" add staged
  printf 'unstaged\n' > "$REPO/tracked"
  printf 'untracked\n' > "$REPO/new"
  printf 'secret\n' > "$REPO/.env"
  mkdir "$REPO/sub"
  printf 'secret\n' > "$REPO/sub/.envrc"
  printf 'ignored\n' > "$REPO/ignored"
  run capture
  [ "$status" -eq 0 ]
  [ "$(mirror_show main staged)" = staged ]
  [ "$(mirror_show main tracked)" = unstaged ]
  [ "$(mirror_show main new)" = untracked ]
  run ! mirror_show main .env 2>/dev/null
  run ! mirror_show main sub/.envrc 2>/dev/null
  run ! mirror_show main ignored 2>/dev/null
}

@test "captures a repo whose secret files are gitignored" {
  printf 'ignored\n.env\n' > "$REPO/.gitignore"
  git -C "$REPO" commit -qam 'ignore env'
  printf 'secret\n' > "$REPO/.env"
  printf 'untracked\n' > "$REPO/new"
  run capture
  [ "$status" -eq 0 ]
  [ "$(mirror_show main new)" = untracked ]
  run ! mirror_show main .env 2>/dev/null
}

@test "does not modify live git metadata and works with index.lock" {
  printf 'changed\n' > "$REPO/tracked"
  touch "$REPO/.git/index.lock"
  local before_index before_status marker
  before_index=$(sha256sum "$REPO/.git/index")
  before_status=$(GIT_OPTIONAL_LOCKS=0 git -C "$REPO" status --porcelain=v2)
  marker="$BATS_TEST_TMPDIR/marker"
  touch "$marker"
  run capture
  [ "$status" -eq 0 ]
  [ "$(sha256sum "$REPO/.git/index")" = "$before_index" ]
  [ "$(GIT_OPTIONAL_LOCKS=0 git -C "$REPO" status --porcelain=v2)" = "$before_status" ]
  [ -z "$(find "$REPO/.git" -newer "$marker" -print)" ]
  [ -f "$REPO/.git/index.lock" ]
}

@test "skips an unchanged repo and captures another edit to an already dirty file" {
  printf 'first\n' > "$REPO/tracked"
  run capture
  [ "$status" -eq 0 ]
  local first
  first=$(git --git-dir="$MIRROR" rev-parse refs/wip/main)
  WIP_CAPTURE_VERBOSE=1 run capture
  [ "$status" -eq 0 ]
  [[ $output == *"skip $REPO"* ]]
  [[ $output == *'skipped=1'* ]]
  [ "$(git --git-dir="$MIRROR" rev-parse refs/wip/main)" = "$first" ]
  printf 'second\n' > "$REPO/tracked"
  run capture
  [ "$status" -eq 0 ]
  [ "$(mirror_show main tracked)" = second ]
  [ "$(git --git-dir="$MIRROR" reflog show refs/wip/main | wc -l)" -eq 2 ]
}

@test "mirrors new commits and stashes" {
  printf 'stash\n' > "$REPO/tracked"
  git -C "$REPO" stash push -q
  run capture
  [ "$status" -eq 0 ]
  [ "$(git --git-dir="$MIRROR" rev-parse refs/stash)" = "$(git -C "$REPO" rev-parse refs/stash)" ]
  printf 'commit\n' > "$REPO/tracked"
  git -C "$REPO" add tracked
  git -C "$REPO" commit -qm next
  run capture
  [ "$status" -eq 0 ]
  [ "$(git --git-dir="$MIRROR" rev-parse HEAD)" = "$(git -C "$REPO" rev-parse HEAD)" ]
  [ "$(mirror_show main tracked)" = commit ]
}

@test "captures linked worktree under the common mirror" {
  linked_fixture
  printf 'worktree\n' > "$ROOT/linked/tracked"
  printf 'staged\n' > "$ROOT/linked/staged"
  git -C "$ROOT/linked" add staged
  printf 'untracked\n' > "$ROOT/linked/untracked"
  run capture
  [ "$status" -eq 0 ]
  [ -f "$MIRROR/worktrees/linked/HEAD" ]
  [ -f "$MIRROR/worktrees/linked/gitdir" ]
  [ ! -e "$MIRROR/worktrees/linked/index" ]
  cmp "$REPO/.git/index" "$MIRROR/index"
  git --git-dir="$MIRROR" ls-tree -r --name-only refs/wip/worktrees/linked/feature > "$BATS_TEST_TMPDIR/snapshot-paths"
  git -C "$ROOT/linked" ls-files --cached --others --exclude-standard | LC_ALL=C sort > "$BATS_TEST_TMPDIR/worktree-paths"
  diff -u "$BATS_TEST_TMPDIR/worktree-paths" "$BATS_TEST_TMPDIR/snapshot-paths"
  for f in .gitignore tracked staged untracked; do
    mirror_show worktrees/linked/feature "$f" > "$BATS_TEST_TMPDIR/snapshot-file"
    cmp "$ROOT/linked/$f" "$BATS_TEST_TMPDIR/snapshot-file"
  done
  [ -n "$(git --git-dir="$MIRROR" reflog show refs/wip/worktrees/linked/feature)" ]
}

@test "removes a deleted worktree's mirrored metadata with a legacy index" {
  linked_fixture
  run capture
  [ "$status" -eq 0 ]
  cp "$REPO/.git/worktrees/linked/index" "$MIRROR/worktrees/linked/index"
  [ -f "$MIRROR/worktrees/linked/index" ]
  git -C "$REPO" worktree remove "$ROOT/linked"
  [ ! -e "$REPO/.git/worktrees/linked" ]
  run capture
  [ "$status" -eq 0 ]
  [[ $output == *'known_broken=0 failures=0'* ]]
  [ ! -e "$MIRROR/worktrees/linked" ]
}

@test "captures a live worktree with a legacy mirrored index" {
  linked_fixture
  run capture
  [ "$status" -eq 0 ]
  cp "$REPO/.git/worktrees/linked/index" "$BATS_TEST_TMPDIR/legacy-index"
  cp "$BATS_TEST_TMPDIR/legacy-index" "$MIRROR/worktrees/linked/index"
  printf 'new staged\n' > "$ROOT/linked/staged"
  git -C "$ROOT/linked" add staged
  git -C "$REPO" update-ref refs/test/force-sync HEAD
  run capture
  [ "$status" -eq 0 ]
  [[ $output == *'known_broken=0 failures=0'* ]]
  [ "$(git --git-dir="$MIRROR" rev-parse refs/test/force-sync)" = "$(git -C "$REPO" rev-parse HEAD)" ]
  cmp "$BATS_TEST_TMPDIR/legacy-index" "$MIRROR/worktrees/linked/index"
  [ "$(mirror_show worktrees/linked/feature staged)" = 'new staged' ]
}

@test "a commit in one worktree syncs the mirror without a new snapshot of its siblings" {
  git clone -q --bare "$REPO" "$BATS_TEST_TMPDIR/remote.git"
  git -C "$REPO" remote add origin "$BATS_TEST_TMPDIR/remote.git"
  use_worktree_lib
  worktree_add_fresh "$REPO" "$ROOT/linked" feature
  printf 'worktree\n' > "$ROOT/linked/tracked"
  run capture
  [ "$status" -eq 0 ]
  printf 'next\n' > "$REPO/tracked"
  git -C "$REPO" commit -qam next
  run capture
  [ "$status" -eq 0 ]
  [ "$(git --git-dir="$MIRROR" rev-parse main)" = "$(git -C "$REPO" rev-parse main)" ]
  [[ $output != *"captured $ROOT/linked"* ]]
  [ "$(git --git-dir="$MIRROR" reflog show refs/wip/worktrees/linked/feature | wc -l)" -eq 1 ]
  run capture
  [[ $output == *'captured=0'* ]]
}

@test "a detached commit in a linked worktree reaches the mirror" {
  git clone -q --bare "$REPO" "$BATS_TEST_TMPDIR/remote.git"
  git -C "$REPO" remote add origin "$BATS_TEST_TMPDIR/remote.git"
  use_worktree_lib
  worktree_add_fresh "$REPO" "$ROOT/linked" feature
  run capture
  [ "$status" -eq 0 ]
  git -C "$ROOT/linked" checkout -q --detach
  printf 'detached\n' > "$ROOT/linked/tracked"
  git -C "$ROOT/linked" commit -qam detached
  printf 'dirty\n' > "$ROOT/linked/tracked"
  local head
  head=$(git -C "$ROOT/linked" rev-parse HEAD)
  run capture
  [ "$status" -eq 0 ]
  [ "$(mirror_show "worktrees/linked/detached-$head" tracked)" = dirty ]
  [ "$(git --git-dir="$MIRROR" rev-parse "refs/wip/worktrees/linked/detached-$head^")" = "$head" ]
}

@test "rejects an unmounted target" {
  export WIP_CAPTURE_ALLOW_DIRECTORY=0
  export WIP_CAPTURE_MOUNT="$BATS_TEST_TMPDIR/unmounted"
  mkdir "$WIP_CAPTURE_MOUNT"
  run capture
  [ "$status" -ne 0 ]
  [[ $output == *'not mounted'* ]]
  [ ! -e "$MIRROR" ]
}

@test "a known-broken checkout warns once and does not fail the run" {
  mkdir "$ROOT/broken"
  printf 'gitdir: /nonexistent\n' > "$ROOT/broken/.git"
  printf 'changed\n' > "$REPO/tracked"
  run capture
  [ "$status" -eq 0 ]
  [[ $output == *'known_broken=1 failures=0'* ]]
  [[ $output == *"warning $ROOT/broken: git directory missing"* ]]
  [ "$(mirror_show main tracked)" = changed ]
  run capture
  [ "$status" -eq 0 ]
  [[ $output == *'known_broken=1'* ]]
  [[ $output != *"warning $ROOT/broken"* ]]
}

@test "an unknown failure still fails the run without blocking other repos" {
  mkdir -p "$ROOT/other"
  git init -q -b main "$ROOT/other"
  mkdir -p "$WIP_CAPTURE_TARGET/dev"
  printf 'not a directory\n' > "$WIP_CAPTURE_TARGET/dev/other"
  printf 'changed\n' > "$REPO/tracked"
  run capture
  [ "$status" -ne 0 ]
  [[ $output == *"failed $ROOT/other"* ]]
  [[ $output == *'failures=1'* ]]
  [ "$(mirror_show main tracked)" = changed ]
}

@test "a capture that times out is a known-broken warning" {
  export WIP_CAPTURE_REPO_TIMEOUT=1
  git -C "$REPO" config filter.slow.clean 'sleep 5; cat'
  printf 'tracked filter=slow\n' > "$REPO/.gitattributes"
  printf 'changed\n' > "$REPO/tracked"
  run capture
  [ "$status" -eq 0 ]
  [[ $output == *"warning $REPO: capture timed out"* ]]
  [[ $output == *'known_broken=1 failures=0'* ]]
}

@test "editing the script during a run does not break the running capture" {
  local copy="$BATS_TEST_TMPDIR/wip_capture.sh"
  cp "$SCRIPT" "$copy"
  for i in 1 2 3 4 5 6; do git init -q -b main "$ROOT/extra$i"; printf 'x\n' > "$ROOT/extra$i/f"; done
  "$copy" "$ROOT" > "$BATS_TEST_TMPDIR/out" 2>&1 &
  local pid=$!
  sleep 0.2
  # Truncate the tail mid-run, as an editor saving a shorter file would.
  head -c 4000 "$SCRIPT" > "$copy"
  printf '\n"unterminated\n' >> "$copy"
  wait "$pid"
  local rc=$?
  cat "$BATS_TEST_TMPDIR/out"
  [ "$rc" -eq 0 ]
  grep -q 'summary repositories=7 captured=7' "$BATS_TEST_TMPDIR/out"
  ! grep -q 'unexpected EOF' "$BATS_TEST_TMPDIR/out"
}

@test "skips large untracked files while retaining small files" {
  truncate -s 50000001 "$REPO/large"
  printf 'small\n' > "$REPO/small"
  run capture
  [ "$status" -eq 0 ]
  [[ $output == *'skip large untracked file:'* ]]
  run ! mirror_show main large 2>/dev/null
  [ "$(mirror_show main small)" = small ]
}

@test "a configured filter cannot write into the live repo" {
  export REPO
  cat > "$BATS_TEST_TMPDIR/filter.sh" <<'FILTER'
#!/usr/bin/env bash
printf 'ran\n' > "$WIP_CAPTURE_STATE/filter-ran"
(printf 'bad\n' > "$REPO/.git/filter-write") 2>/dev/null || :
cat
FILTER
  chmod +x "$BATS_TEST_TMPDIR/filter.sh"
  git -C "$REPO" config filter.probe.clean "$BATS_TEST_TMPDIR/filter.sh"
  printf 'tracked filter=probe\n' > "$REPO/.gitattributes"
  printf 'changed\n' > "$REPO/tracked"
  run capture
  [ "$status" -eq 0 ]
  [ -f "$WIP_CAPTURE_STATE/filter-ran" ]
  [ ! -e "$REPO/.git/filter-write" ]
  [ "$(mirror_show main tracked)" = changed ]
}

@test "captures an unborn branch" {
  mkdir "$ROOT/unborn"
  git init -q -b initial "$ROOT/unborn"
  printf 'new\n' > "$ROOT/unborn/new"
  run capture
  [ "$status" -eq 0 ]
  [ "$(git --git-dir="$WIP_CAPTURE_TARGET/dev/unborn/.git" show refs/wip/initial:new)" = new ]
  [ "$(git --git-dir="$WIP_CAPTURE_TARGET/dev/unborn/.git" rev-list --parents -n 1 refs/wip/initial | wc -w)" -eq 1 ]
}

@test "captures a submodule as a separate repository" {
  git clone -q --bare "$REPO" "$BATS_TEST_TMPDIR/submodule-remote.git"
  git -C "$REPO" -c protocol.file.allow=always submodule add -q "$BATS_TEST_TMPDIR/submodule-remote.git" nested
  printf 'submodule change\n' > "$REPO/nested/tracked"
  run capture
  [ "$status" -eq 0 ]
  [ "$(git --git-dir="$WIP_CAPTURE_TARGET/dev/project/nested/.git" show refs/wip/main:tracked)" = 'submodule change' ]
}

@test "copies alternate object stores into a self-contained mirror" {
  git clone -q --shared "$REPO" "$ROOT/shared"
  printf 'shared change\n' > "$ROOT/shared/tracked"
  run capture
  [ "$status" -eq 0 ]
  local shared_mirror="$WIP_CAPTURE_TARGET/dev/shared/.git"
  [ ! -e "$shared_mirror/objects/info/alternates" ]
  [ "$(git --git-dir="$shared_mirror" show refs/wip/main:tracked)" = 'shared change' ]
  git --git-dir="$shared_mirror" fsck --full
}

@test "mirror metadata remains private under a permissive caller umask" {
  mkdir -p "$REPO/.git/git-crypt/keys"
  printf 'test key\n' > "$REPO/.git/git-crypt/keys/test"
  umask 000
  run capture
  [ "$status" -eq 0 ]
  [ "$(stat -c %a "$MIRROR")" = 700 ]
  [ "$(stat -c %a "$MIRROR/git-crypt/keys/test")" = 600 ]
}

# Stale-capture alert. A repo whose capture times out is never captured; the
# clock is faked with WIP_CAPTURE_NOW and the alert goes to a temp log, never
# the real notifications.log.
stale_setup() {
  export TZ=UTC
  export WIP_CAPTURE_REPO_TIMEOUT=1
  export WIP_CAPTURE_NOTIFY_LOG="$BATS_TEST_TMPDIR/notifications.log"
  T0=1768005000 # 2026-01-10 00:30 UTC
  git -C "$REPO" config filter.slow.clean 'sleep 5; cat'
  printf 'tracked filter=slow\n' > "$REPO/.gitattributes"
  printf 'changed\n' > "$REPO/tracked"
}
capture_at() { WIP_CAPTURE_NOW=$((T0 + $1)) capture; }
alert_count() {
  if [[ -f $WIP_CAPTURE_NOTIFY_LOG ]]; then grep -c service-health "$WIP_CAPTURE_NOTIFY_LOG" || true; else echo 0; fi
}

@test "a repo with no good capture for over 24h raises a service-health alert" {
  stale_setup
  run capture_at 0
  [ "$status" -eq 0 ]
  [ "$(alert_count)" = 0 ]
  run capture_at $((23 * 3600))
  [ "$(alert_count)" = 0 ]
  run capture_at $((25 * 3600))
  [ "$status" -eq 0 ]
  [[ $output == *'alert 1 repos'* ]]
  [ "$(alert_count)" = 1 ]
  run cat "$WIP_CAPTURE_NOTIFY_LOG"
  [[ $output == *$'\tservice-health\t'* ]]
  [[ $output == *"$REPO (capture timed out"* ]]
  [[ $output == *'never captured, failing for 1d 1h'* ]]
}

@test "a second run on the same day sends no second alert" {
  stale_setup
  capture_at 0
  capture_at $((25 * 3600))
  run capture_at $((26 * 3600))
  [[ $output != *'alert '* ]]
  [ "$(alert_count)" = 1 ]
}

@test "a repo still stale the next day alerts again" {
  stale_setup
  capture_at 0
  capture_at $((25 * 3600))
  run capture_at $((49 * 3600))
  [[ $output == *'alert 1 repos'* ]]
  [ "$(alert_count)" = 2 ]
}

@test "a repo captured again sends no alert and the repeats stop" {
  stale_setup
  capture_at 0
  capture_at $((25 * 3600))
  [ "$(alert_count)" = 1 ]
  rm "$REPO/.gitattributes"
  run capture_at $((49 * 3600))
  [ "$status" -eq 0 ]
  [[ $output == *"captured $REPO"* ]]
  [[ $output != *'alert '* ]]
  run capture_at $((73 * 3600))
  [[ $output != *'alert '* ]]
  [ "$(alert_count)" = 1 ]
}

@test "both git wordings for a missing gitdir are a known-broken warning" {
  eval "$(sed -n '/^known_reason() {/,/^}/p' "$SCRIPT")"
  # git 2.43 to 2.53, then git 2.56 and later.
  printf 'fatal: not a git repository: /nonexistent\n' > "$BATS_TEST_TMPDIR/err"
  [ "$(known_reason "$BATS_TEST_TMPDIR/err")" = 'git directory missing (orphan worktree or submodule)' ]
  printf 'fatal: gitfile does not point to a valid repository: /b/.git\n' > "$BATS_TEST_TMPDIR/err"
  [ "$(known_reason "$BATS_TEST_TMPDIR/err")" = 'git directory missing (orphan worktree or submodule)' ]
}

@test "an orphan worktree with nothing to capture never alerts" {
  export TZ=UTC WIP_CAPTURE_NOTIFY_LOG="$BATS_TEST_TMPDIR/notifications.log"
  T0=1768005000
  mkdir "$ROOT/broken"
  printf 'gitdir: /nonexistent\n' > "$ROOT/broken/.git"
  capture_at 0
  run capture_at $((50 * 3600))
  [ "$status" -eq 0 ]
  [[ $output != *'alert '* ]]
  [ "$(alert_count)" = 0 ]
}

@test "a target that stops taking writes mid-run skips the run and keeps the alert clocks" {
  # 2026-11-17: the NAS stalled mid-run and every repo timed out in turn.
  export WIP_CAPTURE_REPO_TIMEOUT=2
  mkdir -p "$WIP_CAPTURE_STATE"
  printf '/elsewhere\t1\n' > "$WIP_CAPTURE_STATE/first-fail.tsv"
  git -C "$REPO" config filter.gone.clean "chmod 500 '$WIP_CAPTURE_TARGET'; sleep 5; cat"
  printf 'tracked filter=gone\n' > "$REPO/.gitattributes"
  printf 'changed\n' > "$REPO/tracked"
  run capture
  chmod 700 "$WIP_CAPTURE_TARGET"
  [ "$status" -eq 75 ]
  [[ $output == *"SUMMARY: skipped, $WIP_CAPTURE_TARGET stopped taking writes mid-run"* ]]
  [[ $output != *'summary repositories='* ]]
  [ "$(cat "$WIP_CAPTURE_STATE/first-fail.tsv")" = "$(printf '/elsewhere\t1')" ]
}
