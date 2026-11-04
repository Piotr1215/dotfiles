#!/usr/bin/env bats

# __sync_with_notify.sh runs under cron, and __cron_run.sh pipes its output
# into the per-job log. Anything it launches inherits that pipe.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__sync_with_notify.sh"
  export HOME="${BATS_TEST_TMPDIR}/home"
  bin_dir="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$HOME" "$bin_dir"
  printf 'export LINEAR_API_KEY=k LINEAR_USER_ID=u\n' > "$HOME/.envrc"
  export SYNC_LOG_FILE="${BATS_TEST_TMPDIR}/sync.log"
  export SYNC_SCRIPT="$bin_dir/sync"
  printf '#!/usr/bin/env bash\necho "ERROR: boom"\nexit 1\n' > "$SYNC_SCRIPT"
  printf '#!/usr/bin/env bash\necho view\n' > "$bin_dir/dunstify"
  # An editor that stays open, like cosmic-edit on the log.
  printf '#!/usr/bin/env bash\nsleep 30\n' > "$bin_dir/xdg-open"
  chmod +x "$SCRIPT" "$bin_dir"/*
  export PATH="$bin_dir:$PATH"
}

@test "a viewer opened from the failure notification does not hold the job open" {
  # Regression: the 09:00 run on 2026-10-14 stayed "running" for as long as
  # the log editor was open, because the editor kept the cron pipe's write end.
  run timeout 5 bash -c '"$0" | cat' "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"FAILED: ERROR: boom"* ]]
}

@test "a successful sync replaces stale failures with the current run" {
  printf 'old failure\n' > "$SYNC_LOG_FILE"
  printf '#!/usr/bin/env bash\necho current-run\n' > "$SYNC_SCRIPT"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  ! grep -q 'old failure' "$SYNC_LOG_FILE"
  grep -q 'current-run' "$SYNC_LOG_FILE"
  grep -q 'OK: github issue sync completed' "$SYNC_LOG_FILE"
}

@test "a command-not-found failure reports the reason and caps the log" {
  seq 1200 > "$SYNC_LOG_FILE"
  printf '#!/usr/bin/env bash\necho "line 1815: asses: command not found" >&2\nexit 127\n' > "$SYNC_SCRIPT"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAILED: line 1815: asses: command not found"* ]]
  [ "$(wc -l < "$SYNC_LOG_FILE")" -le 1000 ]
  grep -q 'FAILED: line 1815: asses: command not found' "$SYNC_LOG_FILE"
}
