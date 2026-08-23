#!/usr/bin/env bats

setup() {
  ACK="${BATS_TEST_DIRNAME}/../../scripts/__cron_ack.sh"
  WIDGET="${BATS_TEST_DIRNAME}/../../.config/argos/cron-status.1m.sh"
  WORK="$(mktemp -d)"
  export CRON_STATE_DIR="${WORK}/state"
  mkdir -p "$CRON_STATE_DIR"
  STATUS="${CRON_STATE_DIR}/job.json"
}

teardown() {
  rm -rf "$WORK"
}

# write_state <state> -> a status file carrying the fields a real run leaves.
write_state() {
  jq -n --arg s "$1" \
    '{job: "job", state: $s, ts: 1787405331, exit_code: 2,
      message: "hit: emailed HTML comparison",
      log_path: "/tmp/job.log"}' >"$STATUS"
}

@test "acking a hit turns it into a no-hit" {
  write_state hit
  run "$ACK" job
  [ "$status" -eq 0 ]
  [ "$(jq -r '.state' "$STATUS")" = "no-hit" ]
}

@test "acking records what it came from and when" {
  write_state hit
  run "$ACK" job
  [ "$status" -eq 0 ]
  [ "$(jq -r '.acked_from' "$STATUS")" = "hit" ]
  [ "$(jq -r '.acked_at | type' "$STATUS")" = "number" ]
}

@test "the run's own history survives the ack" {
  write_state hit
  run "$ACK" job
  [ "$status" -eq 0 ]
  [ "$(jq -r '.message' "$STATUS")" = "hit: emailed HTML comparison" ]
  [ "$(jq -r '.ts' "$STATUS")" = "1787405331" ]
  [ "$(jq -r '.log_path' "$STATUS")" = "/tmp/job.log" ]
  [ "$(jq -r '.exit_code' "$STATUS")" = "2" ]
}

@test "an error cannot be acknowledged away" {
  write_state error
  run "$ACK" job
  [ "$status" -ne 0 ]
  [ "$(jq -r '.state' "$STATUS")" = "error" ]
}

@test "acking twice is refused rather than silently repeated" {
  write_state hit
  run "$ACK" job
  [ "$status" -eq 0 ]
  run "$ACK" job
  [ "$status" -ne 0 ]
  [ "$(jq -r '.state' "$STATUS")" = "no-hit" ]
}

@test "a job with no state on disk is an error, not a new file" {
  run "$ACK" nosuchjob
  [ "$status" -ne 0 ]
  [ ! -e "${CRON_STATE_DIR}/nosuchjob.json" ]
}

@test "the name of the job is required" {
  run "$ACK"
  [ "$status" -ne 0 ]
}

@test "the widget offers mark-as-read only on a hit row" {
  # The widget reads the live crontab, so drive it with a fake `crontab -l`
  # naming one wrapped job whose state we control.
  bin="${WORK}/bin"; mkdir -p "$bin"
  cat >"${bin}/crontab" <<EOF
#!/usr/bin/env bash
echo '0 10 * * MON /home/decoder/dev/dotfiles/scripts/__cron_run.sh job -- /bin/true'
EOF
  chmod +x "${bin}/crontab"

  write_state hit
  run env PATH="${bin}:${PATH}" "$WIDGET"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mark as read"* ]]

  write_state no-hit
  run env PATH="${bin}:${PATH}" "$WIDGET"
  [ "$status" -eq 0 ]
  [[ "$output" != *"mark as read"* ]]

  write_state error
  run env PATH="${bin}:${PATH}" "$WIDGET"
  [ "$status" -eq 0 ]
  [[ "$output" != *"mark as read"* ]]
}
