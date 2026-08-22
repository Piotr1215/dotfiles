#!/usr/bin/env bash
# PROJECT: cron-manager
#
# Run one registered cron job right now, exactly as cron would.
#
# The command comes out of the crontab line itself rather than being passed
# in, so a forced run cannot drift from the scheduled one: same wrapper, same
# job name, same arguments. State lands in ~/.local/state/cron-jobs/ the way
# a scheduled run's would, so the widget and dashboard reflect it immediately.
#
# Usage: __cron_trigger.sh <job-name>
set -eo pipefail

# cron itself runs with a bare environment; these two are what the crontab
# sets for jobs that touch the desktop session (notifications, clipboard).
export DISPLAY="${DISPLAY:-:1}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/1000/bus}"

job="${1:-}"
if [ -z "$job" ]; then
    echo "usage: $(basename "$0") <job-name>" >&2
    exit 64
fi

# Find the wrapped line naming exactly this job. The trailing space in the
# match guards against a prefix collision (a job named `foo` must not match
# the line for `foo-full`).
line=$(crontab -l 2>/dev/null | grep -v '^[[:space:]]*#' |
    grep -F "__cron_run.sh ${job} " | head -1 || true)

if [ -z "$line" ]; then
    echo "No wrapped crontab entry found for job '${job}'." >&2
    echo "Only jobs routed through __cron_run.sh can be triggered this way." >&2
    exit 1
fi

# Keep everything from the wrapper call onward, dropping the schedule fields
# and any leading inline env assignments, which are re-applied below.
cmd=${line#*__cron_run.sh}
cmd="$HOME/dev/dotfiles/scripts/__cron_run.sh${cmd}"

# Re-apply inline env assignments that sat between the schedule and the
# wrapper (R2R_PR_SYNC=0 and friends), so a forced run matches the scheduled
# one rather than silently taking different defaults.
env_prefix=$(grep -oE '[A-Z_][A-Z0-9_]*=[^ ]+' <<<"${line%%__cron_run.sh*}" | tr '\n' ' ')

echo "Running ${job} now, as cron would:"
echo "  ${env_prefix}${cmd}"
echo

set +e
eval "${env_prefix}${cmd}"
code=$?
set -e

echo
case "$code" in
    0) echo "Finished: no-hit (ran clean, nothing notable)." ;;
    2) echo "Finished: hit (found something worth surfacing)." ;;
    *) echo "Finished: error (exit ${code})." ;;
esac
echo "State written to ~/.local/state/cron-jobs/${job}.json"
echo
read -rp "Press Enter to close..." _
