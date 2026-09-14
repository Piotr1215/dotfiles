#!/usr/bin/env bats

# __backup_watchdog.sh is the dead-man's switch for the nightly backup. Its alert
# paths must exit 2 with the reason on stdout: the cron wrapper records exit 2 as
# a hit and lifts the last stdout line onto the dashboard. They used to exit 0
# with no output, so a 62h-old stamp painted green on 09-13 and 09-14 (#181).

setup() {
  WATCHDOG="${BATS_TEST_DIRNAME}/../../scripts/__backup_watchdog.sh"
  CRON_RUN="${BATS_TEST_DIRNAME}/../../scripts/__cron_run.sh"
  WORK="$(mktemp -d)"
  CALLS="${WORK}/alert-calls"

  export BACKUP_SUCCESS_STAMP="${WORK}/backup-last-success"
  export CRON_STATE_DIR="${WORK}/state"
  unset MAX_AGE_HOURS

  # Stand-ins for the alert channels, so a test never mails or pops up anything.
  mkdir -p "${WORK}/bin"
  cat >"${WORK}/bin/msmtp" <<EOF
#!/usr/bin/env bash
cat >/dev/null
echo msmtp >>"${CALLS}"
EOF
  cat >"${WORK}/bin/notify-send" <<EOF
#!/usr/bin/env bash
echo notify-send >>"${CALLS}"
EOF
  chmod +x "${WORK}/bin/msmtp" "${WORK}/bin/notify-send"
  export PATH="${WORK}/bin:${PATH}"
}

teardown() {
  rm -rf "$WORK"
}

stamp_hours_ago() {
  echo $(($(date +%s) - $1 * 3600)) >"$BACKUP_SUCCESS_STAMP"
}

@test "a fresh stamp exits 0 with an OK line and sends no alert" {
  stamp_hours_ago 0

  run "$WATCHDOG"

  [ "$status" -eq 0 ]
  [ "$output" = "OK: last successful backup 0h ago" ]
  [ ! -e "$CALLS" ]
}

@test "a missing stamp exits 2, says why on stdout, and alerts both channels" {
  run "$WATCHDOG"

  [ "$status" -eq 2 ]
  [[ "$output" == "ALERT: No successful backup on record"* ]]
  grep -qx msmtp "$CALLS"
  grep -qx notify-send "$CALLS"
}

@test "a stamp past the threshold exits 2 and names its age" {
  stamp_hours_ago 30

  run "$WATCHDOG"

  [ "$status" -eq 2 ]
  [[ "$output" == "ALERT: Last successful backup was 30h ago (threshold 25h)"* ]]
  grep -qx msmtp "$CALLS"
}

@test "MAX_AGE_HOURS moves the threshold" {
  stamp_hours_ago 30

  MAX_AGE_HOURS=48 run "$WATCHDOG"

  [ "$status" -eq 0 ]
  [ "$output" = "OK: last successful backup 30h ago" ]
  [ ! -e "$CALLS" ]
}

@test "through the cron wrapper a stale stamp is recorded as a hit with the alert as its message" {
  stamp_hours_ago 62

  run "$CRON_RUN" backup-watchdog-test -- "$WATCHDOG"

  state="${CRON_STATE_DIR}/backup-watchdog-test.json"
  [ "$(jq -r .state "$state")" = "hit" ]
  [ "$(jq -r .exit_code "$state")" = "2" ]
  [[ "$(jq -r .message "$state")" == *"ALERT: Last successful backup was 62h ago"* ]]
}

@test "through the cron wrapper a fresh stamp is recorded as no-hit" {
  stamp_hours_ago 1

  run "$CRON_RUN" backup-watchdog-test -- "$WATCHDOG"

  state="${CRON_STATE_DIR}/backup-watchdog-test.json"
  [ "$(jq -r .state "$state")" = "no-hit" ]
  [[ "$(jq -r .message "$state")" == *"OK: last successful backup 1h ago"* ]]
}
