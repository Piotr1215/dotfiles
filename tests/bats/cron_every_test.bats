#!/usr/bin/env bats

# __cron_every.sh is anacron's idea kept inside cron: the crontab line fires
# often, the guard no-ops until the interval has elapsed. The stamp advancing
# only on a clean run is what makes a failed attempt retry on the next tick
# instead of being marked done for another week.

setup() {
  CRON_EVERY="${BATS_TEST_DIRNAME}/../../scripts/__cron_every.sh"
  WORK="$(mktemp -d)"

  export CRON_EVERY_STAMP_DIR="${WORK}/stamps"
  STAMP="${CRON_EVERY_STAMP_DIR}/weekly"
  MARKER="${WORK}/ran"
  JOB="${WORK}/job.sh"
}

teardown() {
  rm -rf "$WORK"
}

# job_exiting <code>: a command that records each invocation, then exits.
job_exiting() {
  cat >"$JOB" <<EOF
#!/usr/bin/env bash
printf 'x' >>"${MARKER}"
echo "job ran"
exit ${1}
EOF
  chmod +x "$JOB"
}

run_count() {
  if [ -f "$MARKER" ]; then wc -c <"$MARKER"; else echo 0; fi
}

@test "the first run with no stamp executes the command" {
  job_exiting 0

  run "$CRON_EVERY" weekly 3600 -- "$JOB"

  [ "$status" -eq 0 ]
  [[ "$output" == *"job ran"* ]]
  [ "$(run_count)" -eq 1 ]
  [ -f "$STAMP" ]
}

@test "a second run inside the interval is a silent no-op" {
  job_exiting 0
  run "$CRON_EVERY" weekly 3600 -- "$JOB"
  [ "$status" -eq 0 ]

  run "$CRON_EVERY" weekly 3600 -- "$JOB"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(run_count)" -eq 1 ]
}

@test "an elapsed interval lets the command run again and advances the stamp" {
  job_exiting 0
  mkdir -p "$CRON_EVERY_STAMP_DIR"
  stale=$(( $(date +%s) - 7200 ))
  printf '%s\n' "$stale" >"$STAMP"

  run "$CRON_EVERY" weekly 3600 -- "$JOB"

  [ "$status" -eq 0 ]
  [ "$(run_count)" -eq 1 ]
  [ "$(cat "$STAMP")" -gt "$stale" ]
}

@test "a failing command leaves the stamp alone so the next tick retries" {
  job_exiting 1
  mkdir -p "$CRON_EVERY_STAMP_DIR"
  stale=$(( $(date +%s) - 7200 ))
  printf '%s\n' "$stale" >"$STAMP"

  run "$CRON_EVERY" weekly 3600 -- "$JOB"
  [ "$status" -eq 1 ]
  [ "$(cat "$STAMP")" -eq "$stale" ]

  run "$CRON_EVERY" weekly 3600 -- "$JOB"

  [ "$status" -eq 1 ]
  [ "$(run_count)" -eq 2 ]
}

@test "a hit advances the stamp and passes exit 2 through untouched" {
  job_exiting 2

  run "$CRON_EVERY" weekly 3600 -- "$JOB"
  [ "$status" -eq 2 ]
  [ -f "$STAMP" ]

  run "$CRON_EVERY" weekly 3600 -- "$JOB"

  [ "$status" -eq 0 ]
  [ "$(run_count)" -eq 1 ]
}

@test "a missing interval is a usage error" {
  run "$CRON_EVERY" weekly

  [ "$status" -eq 64 ]
  [[ "$output" == *"usage:"* ]]
}

@test "a missing command is a usage error" {
  run "$CRON_EVERY" weekly 3600 --

  [ "$status" -eq 64 ]
  [[ "$output" == *"usage:"* ]]
}

@test "a non-numeric interval is rejected" {
  job_exiting 0

  run "$CRON_EVERY" weekly weekly -- "$JOB"

  [ "$status" -eq 64 ]
  [[ "$output" == *"interval must be whole seconds"* ]]
  [ "$(run_count)" -eq 0 ]
}
