#!/usr/bin/env bash
# PROJECT: cron-manager
#
# Marks a job's `hit` as read, so the green ★ on the argos badge clears
# without waiting for the job's next scheduled run.
#
# A hit means "ran clean, found something worth your attention" and the badge
# is latched to the last run's exit code, so it stands until the job runs
# again. For a watcher on `0 10 * * MON,WED,FRI` that is up to two days of a
# star pointing at mail already read, which is how a badge learns to be
# ignored. Acking rewrites .state to no-hit and records what it came from,
# leaving message, ts and log_path untouched: the run's history survives, only
# the call to action goes away.
#
# Errors are deliberately not ackable. Red means the latest run FAILED and
# wants fixing; a dismiss button there would hide a real failure behind one
# click. The one signal that must stay trustworthy has no snooze.
#
# Usage: __cron_ack.sh <job-name>
set -eo pipefail
IFS=$'\n\t'

STATE_DIR="${CRON_STATE_DIR:-$HOME/.local/state/cron-jobs}"

job="${1:-}"
if [ -z "$job" ]; then
	echo "usage: __cron_ack.sh <job-name>" >&2
	exit 1
fi

status_file="${STATE_DIR}/${job}.json"
if [ ! -f "$status_file" ]; then
	echo "no state for '${job}' at ${status_file}" >&2
	exit 1
fi

state="$(jq -r '.state // ""' "$status_file" 2>/dev/null || echo "")"
if [ "$state" != "hit" ]; then
	echo "'${job}' is ${state:-unknown}, not a hit: nothing to acknowledge" >&2
	exit 1
fi

# Atomic replace, and into the same directory: the widget reads these files on
# a one-minute tick and a partial write would render as a state of "?".
tmp="$(mktemp "${status_file}.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
jq --argjson now "$(date +%s)" \
	'.state = "no-hit" | .acked_from = "hit" | .acked_at = $now' \
	"$status_file" >"$tmp"
mv "$tmp" "$status_file"
trap - EXIT

echo "acknowledged hit for ${job}"
