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

# This runs inside a throwaway alacritty window, so anything that exits before
# the final prompt takes its own error message off the screen with it. That is
# how a `grep` returning 1 under `set -e` became "I clicked run and nothing
# happened". Hold the window open on any abort and say where it died.
finished=0
# shellcheck disable=SC2154  # rc and msg are assigned inside the trap body
trap 'rc=$?; if [ "$finished" -eq 0 ]; then
        msg="cron-trigger aborted (exit $rc) at line ${BASH_LINENO[0]}, job=${job:-<unset>}"
        if [ -t 1 ]; then
          printf "\n!! %s\n\n" "$msg"
          read -rp "Press Enter to close..." _
        else
          notify-send -u critical "cron-manager" "$msg" 2>/dev/null || true
        fi
      fi' EXIT

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
#
# The `|| true` is not cosmetic: most crontab lines carry no inline env at
# all, grep exits 1 on no match, and under `set -eo pipefail` that killed the
# script before its first echo. A click on "run now" then opened alacritty and
# closed it again with nothing shown, so the job silently never ran.
env_prefix=$(grep -oE '[A-Z_][A-Z0-9_]*=[^ ]+' <<<"${line%%__cron_run.sh*}" | tr '\n' ' ' || true)

status_file="${HOME}/.local/state/cron-jobs/${job}.json"

# Clicked from the panel there is no terminal, and opening one for a job that
# reports through the widget anyway was just a window flashing past. Detach the
# run, wait only until it has published its running marker, and exit so argos
# refreshes onto a purple row. Argos refreshes a `bash=` action through
# child_watch_add, i.e. after the command exits, so returning early here is
# exactly what makes the icon flip immediately instead of at the next tick.
if [ ! -t 1 ]; then
    setsid bash -c "${env_prefix}${cmd}" >/dev/null 2>&1 &
    for _ in $(seq 1 50); do
        if [ -f "$status_file" ] &&
           [ "$(jq -r '.state // ""' "$status_file" 2>/dev/null)" = "running" ]; then
            break
        fi
        sleep 0.1
    done
    finished=1
    exit 0
fi

# A terminal is attached (run by hand, or by the cron-manager agent), so report
# inline and block until read.
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
finished=1
