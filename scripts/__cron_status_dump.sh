#!/usr/bin/env bash
# PROJECT: cron-manager
# Prints a plain-text status table of every locally scheduled cron job, for
# the cron-manager tmuxinator session's status pane (run under `viddy`).
#
# State source, per job (in priority order):
#   1. ~/.local/state/cron-jobs/<job>.json, written by __cron_run.sh: {ts,
#      state, message}. Jobs not yet migrated to the wrapper have no such
#      file, which is expected, not an error.
#   2. Fallback: the mtime of whatever log file the crontab line redirects
#      to (`>> path.log`), as a last-ran proxy. No redirect -> "unknown".
#
# This is deliberately a thin read-only view: it never edits crontab, never
# launches anything. /ops-cron-manager does the deeper diagnosis.
set -eo pipefail

STATE_DIR="${CRON_STATE_DIR:-$HOME/.local/state/cron-jobs}"
NEXT_RUN="$HOME/dev/dotfiles/scripts/__cron_next_run.py"

human_age() {
    local then="$1" now delta
    now=$(date +%s)
    delta=$(( now - then ))
    if   [ "$delta" -lt 60 ]; then echo "${delta}s"
    elif [ "$delta" -lt 3600 ]; then echo "$(( delta / 60 ))m"
    elif [ "$delta" -lt 86400 ]; then echo "$(( delta / 3600 ))h"
    else echo "$(( delta / 86400 ))d"
    fi
}

state_glyph() {
    case "$1" in
        no-hit) echo "🟢" ;;
        hit) echo "🟢" ;;
        error) echo "🔴" ;;
        # Amber, alongside stale, and pointedly not red. Red means the last run
        # failed and wants diagnosing; interrupted means something took the
        # machine away mid-run and the job just wants running again.
        interrupted) echo "🟠" ;;
        stale) echo "🟠" ;;
        # Ran clean and said its purpose is over (a tripped verificator).
        spent) echo "✅" ;;
        pending) echo "🔵" ;;
        running) echo "🟣" ;;
        *) echo "⚫" ;;
    esac
}

# Parser and staleness budget are shared with the argos widget.
# shellcheck source=/home/decoder/dev/dotfiles/scripts/__lib_cron_view.sh
source "$HOME/dev/dotfiles/scripts/__lib_cron_view.sh"

printf '%-34s %-54s %-19s %-4s %-9s %-7s %s\n' "JOB" "WHAT IT DOES" "SCHEDULE" "" "LAST" "NEXT" "NOTE"
printf '%s\n' "-------------------------------------------------------------------------------------------------------------------------------------------------"

while IFS=$'\t' read -r schedule job cmd purpose; do
    ts=""
    status_file="${STATE_DIR}/${job}.json"
    if [ -f "$status_file" ]; then
        ts=$(jq -r '.ts // empty' "$status_file" 2>/dev/null)
        state=$(jq -r '.state // "?"' "$status_file" 2>/dev/null)
        msg=$(jq -r '.message // ""' "$status_file" 2>/dev/null)
        last=$( [ -n "$ts" ] && human_age "$ts" || echo "unknown" )
        # The wrapper reports the last run. Whether there has been one lately
        # is a separate question, and the one a green state file cannot answer.
        case "$state" in
            hit|no-hit)
                if cron_spent "$msg"; then
                    state="spent"
                    msg="tripped, still scheduled: retire this line"
                elif cron_overdue "$ts" "$schedule" "$cmd"; then
                    state="stale"
                    msg="overdue: last ran ${last} ago, stopped firing"
                fi
                ;;
        esac
    else
        # Fallback: last-write time of a redirected log, if the line has one.
        # No redirect is the common case, so a non-match must not abort the loop.
        logpath=$(grep -oE '>>?\s*[^ ]+\.log' <<<"$cmd" | awk '{print $NF}' | tail -1 || true)
        if [ -n "$logpath" ] && [ -f "${logpath/#\~/$HOME}" ]; then
            ts=$(stat -c %Y "${logpath/#\~/$HOME}" 2>/dev/null || echo "")
            last=$( [ -n "$ts" ] && human_age "$ts" || echo "unknown" )
            if cron_overdue "$ts" "$schedule" "$cmd"; then
                state="stale"
                msg="overdue, stopped firing"
            else
                state="no-hit"
                msg="ok (from log mtime)"
            fi
        elif [[ "$cmd" == *__cron_run.sh* ]]; then
            # Wrapped but not yet run since; waiting, not unknowable.
            last="-"
            state="pending"
            msg="awaiting first run"
        else
            last="unknown"
            state="?"
            msg="no signal available"
        fi
    fi

    next=$(printf '%s\n' "$schedule" | "$NEXT_RUN" 2>/dev/null || echo "-")
    [ "${#purpose}" -gt 54 ] && purpose="${purpose:0:53}…"
    printf '%-34s %-54s %-19s %-4s %-9s %-7s %s\n' "$job" "$purpose" "$(cron_human_schedule "$schedule" "$cmd")" "$(state_glyph "$state")" "$last" "$next" "$msg"
done < <(cron_registry)

printf '\n%s\n' "Wrapper-reported jobs show real state (no-hit/hit/error). Everything else is a best-effort guess from log mtimes; route through __cron_run.sh to get real signal. Reminders are not listed: the reminders applet owns them."
