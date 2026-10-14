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
