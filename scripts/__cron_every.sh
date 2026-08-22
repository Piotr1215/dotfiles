#!/usr/bin/env bash
# PROJECT: cron-manager
# Interval guard for cron jobs on a machine that is not on 24/7.
#
# This box is powered off roughly 23:30-09:00 every day, so a job pinned to a
# clock time in that window never fires at all: user crontabs have no catch-up.
# Two weekly R2R healing jobs sat at 03:30 and 04:30 on Sunday and had never
# run once in four weeks of journal history.
#
# The fix is anacron's idea, kept inside cron: check often, act rarely. Run the
# line on a frequent schedule that is certain to land while the machine is
# awake, and let this guard no-op until the interval has actually elapsed.
#
# Usage in crontab, inside the state wrapper:
#   0 * * * * __cron_run.sh <job> -- __cron_every.sh <stamp> 604800 -- <command...>
#
# The stamp advances only on a successful run (exit 0 or 2), so a failed or
# interrupted attempt is retried on the next tick instead of being marked done
# for another week. The wrapped command's exit code passes through untouched,
# which keeps the 0/2/other state channel that __cron_run.sh reads intact.
set -eo pipefail

STAMP_DIR="${CRON_EVERY_STAMP_DIR:-$HOME/.local/state/cron-every}"

stamp_name="$1"; shift || true
interval="$1"; shift || true
if [ "$1" = "--" ]; then shift; fi

if [ -z "$stamp_name" ] || [ -z "$interval" ] || [ $# -eq 0 ]; then
    echo "usage: $(basename "$0") <stamp-name> <min-interval-seconds> -- <command...>" >&2
    exit 64
fi
case "$interval" in
    ''|*[!0-9]*) echo "interval must be whole seconds, got: $interval" >&2; exit 64 ;;
esac

mkdir -p "$STAMP_DIR"
stamp_file="${STAMP_DIR}/${stamp_name}"
now=$(date +%s)

if [ -f "$stamp_file" ]; then
    last=$(cat "$stamp_file" 2>/dev/null || echo 0)
    case "$last" in ''|*[!0-9]*) last=0 ;; esac
    elapsed=$(( now - last ))
    if [ "$elapsed" -lt "$interval" ]; then
        # Not due. Silent by design: this is the common case, several times a
        # day, and saying so would drown the log the one time it matters.
        exit 0
    fi
fi

"$@" && code=0 || code=$?

# Advance the stamp only on a clean run. 2 is `hit` (ran fine, found something
# worth surfacing), so it counts as done; anything else is left for a retry.
if [ "$code" -eq 0 ] || [ "$code" -eq 2 ]; then
    printf '%s\n' "$now" > "$stamp_file"
fi

exit "$code"
