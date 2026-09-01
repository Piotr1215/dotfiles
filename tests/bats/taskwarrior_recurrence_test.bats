#!/usr/bin/env bats

setup() {
  REPO="${BATS_TEST_DIRNAME}/../.."
  CRON_RUN="${REPO}/scripts/__cron_run.sh"
  TASKRC_FILE="${REPO}/.taskrc"
  WORK="$(mktemp -d)"
  BIN="${WORK}/bin"
  mkdir -p "$BIN"

  export CRON_STATE_DIR="${WORK}/state"
  export TASKWARRIOR_RECURRENCE_LOCK="${WORK}/recurrence.lock"
}

teardown() {
  rm -rf "$WORK"
}

wait_for_file() {
  local path="$1"
  for _ in $(seq 1 200); do
    [ -e "$path" ] && return 0
    sleep 0.01
  done
  return 1
}

make_job() {
  local name="$1" marker="$2"
  printf '#!/usr/bin/env bash\nprintf "started\\n" >%q\n' "$marker" >"${BIN}/${name}"
  chmod +x "${BIN}/${name}"
}

@test "recurrence expansion is disabled for ordinary task commands" {
  run env TASKRC="$TASKRC_FILE" task rc.data.location="$WORK/data" show recurrence

  [ "$status" -eq 0 ]
  [[ "$output" =~ recurrence[[:space:]]+0 ]]
}

@test "concurrent cron jobs share one short recurrence preflight, not a whole-job lock" {
  export TASK_CALLS="${WORK}/task-calls" TASK_STARTED="${WORK}/task-started"
  export TASK_RELEASE="${WORK}/task-release" PATH="${BIN}:${PATH}"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"$TASK_CALLS"\n: >"$TASK_STARTED"\nwhile [ ! -e "$TASK_RELEASE" ]; do sleep 0.01; done\n' >"${BIN}/task"
  chmod +x "${BIN}/task"
  make_job first-job "${WORK}/first-started"
  make_job second-job "${WORK}/second-started"

  "$CRON_RUN" first -- "${BIN}/first-job" & first_pid=$!
  wait_for_file "$TASK_STARTED"
  "$CRON_RUN" second -- "${BIN}/second-job" & second_pid=$!
  wait_for_file "${WORK}/second-started"
  : >"$TASK_RELEASE"
  wait "$first_pid"; wait "$second_pid"

  [ "$(wc -l <"$TASK_CALLS")" -eq 1 ]
  [ "$(cat "$TASK_CALLS")" = "rc.context=none rc.recurrence=1 rc.verbose=nothing count" ]
  [ -e "${WORK}/first-started" ]
}

@test "a failed recurrence preflight does not fail the wrapped job" {
  printf '#!/usr/bin/env bash\necho "recurrence failed" >&2\nexit 7\n' >"${BIN}/task"
  chmod +x "${BIN}/task"
  make_job clean-job "${WORK}/job-started"

  run env PATH="${BIN}:${PATH}" "$CRON_RUN" job -- "${BIN}/clean-job"

  [ "$status" -eq 0 ]
  [ -e "${WORK}/job-started" ]
  run grep -F "recurrence expansion failed: recurrence failed" "${CRON_STATE_DIR}/job.log"
  [ "$status" -eq 0 ]
}
