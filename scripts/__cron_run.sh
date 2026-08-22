#!/usr/bin/env bash
# PROJECT: cron-manager
# Generic cron wrapper: runs a command, times it, captures its output, and
# writes one JSON status file so cron-manager (the argos widget and the
# tmuxinator dashboard) can show real per-job state instead of guessing from
# log mtimes.
#
# Usage in crontab:
#   M H DoM Mon DoW  /path/__cron_run.sh <job-name> -- <command...>
#
# State is read from the wrapped command's EXIT CODE, chronic-style (silent
# unless there's something to say):
#   0        -> no-hit  (ran clean, nothing notable)
#   2        -> hit     (ran clean, found something worth surfacing)
#   anything else -> error
# A job that wants to report "hit" must exit 2 on that path itself; there is
# no other signal channel. Anything the wrapper can't attribute to the job
# (it crashing before this convention, a shell error) still lands as `error`,
# never silently as `no-hit` — an unrecognized non-zero/non-2 code is `error`.
set -eo pipefail

STATE_DIR="${CRON_STATE_DIR:-$HOME/.local/state/cron-jobs}"
mkdir -p "$STATE_DIR"

job="$1"; shift
if [ "$1" = "--" ]; then shift; fi
if [ -z "$job" ] || [ $# -eq 0 ]; then
    echo "usage: $(basename "$0") <job-name> -- <command...>" >&2
    exit 64
fi

status_file="${STATE_DIR}/${job}.json"
log_file="${STATE_DIR}/${job}.log"

start_ts=$(date +%s)
output=$("$@" 2>&1) && code=0 || code=$?
end_ts=$(date +%s)
duration=$(( end_ts - start_ts ))

# Keep the last run's full output for the dashboard/agent to inspect, and the
# last line as the at-a-glance message (most scripts put their summary there).
printf '%s\n' "$output" > "$log_file"
last_line=$(printf '%s\n' "$output" | tail -1)

case "$code" in
    0) state="no-hit" ;;
    2) state="hit" ;;
    *) state="error" ;;
esac

tmp="$(mktemp)"
jq -n --arg job "$job" --argjson ts "$end_ts" --arg state "$state" \
    --argjson exit_code "$code" --argjson duration "$duration" \
    --arg message "$last_line" --arg log_path "$log_file" \
    '{job: $job, ts: $ts, state: $state, exit_code: $exit_code, duration_s: $duration, message: $message, log_path: $log_path}' \
    > "$tmp"
mv "$tmp" "$status_file"

# Never swallow output: cron's own mailer still sees stdout/stderr on error,
# so a job silently unwired from this convention doesn't go dark either.
printf '%s\n' "$output"
[ "$state" = "error" ] && exit "$code"
exit 0
