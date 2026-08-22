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

# Publish a running marker before handing off, so a job in flight is visible
# rather than looking idle at its last result for however long it takes. The
# PID lets a reader tell a live run from one whose process died without ever
# writing a final state.
running_tmp="$(mktemp)"
jq -n --arg job "$job" --argjson ts "$start_ts" --argjson pid "$$" \
    '{job: $job, ts: $ts, state: "running", pid: $pid}' >"$running_tmp"
mv "$running_tmp" "$status_file"

output=$("$@" 2>&1) && code=0 || code=$?
end_ts=$(date +%s)
duration=$(( end_ts - start_ts ))

# Keep the last run's full output for the dashboard/agent to inspect, and the
# last line as the at-a-glance message (most scripts put their summary there).
#
# Strip ANSI escapes on the way in: tools that colour their output (direnv's
# "loading ~/.envrc" banner is the one that showed up here) write raw escapes
# that render as junk in an editor and pollute the message field.
clean=$(printf '%s' "$output" | sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g')

# A silent run means an empty log, not a file holding one newline.
if [ -n "$clean" ]; then
    printf '%s\n' "$clean" > "$log_file"
else
    : > "$log_file"
fi
last_line=$(printf '%s' "$clean" | grep -v '^[[:space:]]*$' | tail -1 || true)

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

# Surface output only when there is something to say: an `error` or a `hit`.
# A clean no-hit run stays silent, so cron's mailer is not handed a payload on
# every tick. That matters here because sending fails (msmtp passwordeval
# cannot reach the password store under cron), so every emitted byte becomes a
# failed-delivery line in the journal rather than a mail. The full output is
# still written to $log_file above regardless of state, so nothing goes dark.
if [ "$state" != "no-hit" ]; then
    printf '%s\n' "$output"
fi
[ "$state" = "error" ] && exit "$code"
exit 0
