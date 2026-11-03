#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home" CRON_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CRON_REGISTRY_FILE="$BATS_TEST_TMPDIR/crontab" CALLS="$BATS_TEST_TMPDIR/calls"
  mkdir -p "$HOME/dev/dotfiles/scripts" "$CRON_STATE_DIR" "$BATS_TEST_TMPDIR/bin"
  cp "$BATS_TEST_DIRNAME/../../scripts/"{__lib_cron_view.sh,__cron_next_run.py} "$HOME/dev/dotfiles/scripts/"
  cat > "$BATS_TEST_TMPDIR/bin/python3" <<'STUB'
#!/bin/bash
echo python >> "$CALLS"
exec /usr/bin/python3 "$@"
STUB
  cat > "$BATS_TEST_TMPDIR/bin/jq" <<'STUB'
#!/bin/bash
echo jq >> "$CALLS"
exit 1
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/"*
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  WIDGET="$BATS_TEST_DIRNAME/../../.config/argos/cron-status.1m.sh"
}
@test "batch keeps state and menu rows while starting one python and no jq" {
  cat > "$CRON_REGISTRY_FILE" <<'CRON'
# first job
* * * * * /tmp/__cron_run.sh first -- /bin/true
# second job
@reboot /tmp/__cron_run.sh second -- /bin/true
# third job
0 10 * * * /tmp/__cron_run.sh third -- /bin/true
CRON
  printf '{"state":"hit","message":"hello", "ts":%s}' "$(date +%s)" > "$CRON_STATE_DIR/first.json"
  printf '{"state":"error","message":"bad"}' > "$CRON_STATE_DIR/second.json"
  run bash "$WIDGET"
  [ "$status" -eq 0 ]
  [[ "$output" == *'1!'* && "$output" == *'mark as read'* && "$output" == *'second failed: bad'* ]]
  [[ "$output" == *'first job'* && "$output" == *'third job'* ]]
  [ "$(cat "$CALLS")" = python ]
}
@test "empty registry has no phantom job" {
  : > "$CRON_REGISTRY_FILE"
  run bash "$WIDGET"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Nothing needs you.'* && "$output" != *'run now'* ]]
}

@test "overdue checks share the supplied clock and fall back when absent" {
  cat > "$BATS_TEST_TMPDIR/bin/date" <<'STUB'
#!/bin/bash
echo date >> "$CALLS"
printf '1000000\n'
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/date"
  run bash -c '
    source "$1"
    CRON_VIEW_NOW=1000000
    cron_overdue 800000 "0 10 * * *" "" || exit 1
    cron_overdue 999999 "0 10 * * *" "" && exit 1
    unset CRON_VIEW_NOW
    cron_overdue 800000 "0 10 * * *" "" || exit 1
  ' _ "$BATS_TEST_DIRNAME/../../scripts/__lib_cron_view.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$CALLS")" = date ]
}
