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

human_age() {
    local then="$1" now delta
    now=$(date +%s)
    delta=$(( now - then ))
    if   [ "$delta" -lt 60 ]; then echo "${delta}s ago"
    elif [ "$delta" -lt 3600 ]; then echo "$(( delta / 60 ))m ago"
    elif [ "$delta" -lt 86400 ]; then echo "$(( delta / 3600 ))h ago"
    else echo "$(( delta / 86400 ))d ago"
    fi
}

state_glyph() {
    case "$1" in
        no-hit) echo "🟢" ;;
        hit) echo "🟢" ;;
        error) echo "🔴" ;;
        stale) echo "🟠" ;;
        pending) echo "🔵" ;;
        *) echo "⚫" ;;
    esac
}

# Rough upper bound, in seconds, on how long a job may legitimately go quiet.
# Only precise enough to separate "ran on schedule" from "silently stopped".
expected_interval() {
    local sched="$1" min hour dom mon dow
    case "$sched" in
        @reboot) echo 2592000; return ;;
        @daily|@midnight) echo 172800; return ;;
        @hourly) echo 7200; return ;;
        @weekly) echo 1209600; return ;;
        @monthly) echo 5184000; return ;;
    esac
    read -r min hour dom mon dow <<<"$sched"
    if [[ "$min" == */* ]]; then echo $(( ${min#*/} * 60 * 2 )); return; fi
    if [[ "$min" == *,* ]]; then echo 7200; return; fi
    if [[ "$hour" == "*" ]]; then echo 7200; return; fi
    if [[ "$hour" == */* ]]; then echo $(( ${hour#*/} * 3600 * 2 )); return; fi
    if [[ "$dow" != "*" || "$dom" != "*" || "$mon" != "*" ]]; then echo 1209600; return; fi
    echo 172800
}

printf '%-28s %-15s %-5s %-12s %s\n' "JOB" "SCHEDULE" "STATE" "LAST RUN" "MESSAGE"
printf '%s\n' "--------------------------------------------------------------------------------"

crontab -l 2>/dev/null | while IFS= read -r line; do
    # Skip comments, blank lines, and bare env-var assignments (no leading whitespace, no digit/*/@ start).
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] && continue

    # First 5 whitespace-separated fields are the schedule; @special forms count as one field.
    if [[ "$line" == @* ]]; then
        schedule=$(awk '{print $1}' <<<"$line")
        cmd=$(awk '{$1=""; print substr($0,2)}' <<<"$line")
    else
        schedule=$(awk '{print $1, $2, $3, $4, $5}' <<<"$line")
        cmd=$(awk '{for(i=6;i<=NF;i++) printf "%s ", $i; print ""}' <<<"$line")
    fi

    # A wrapped line names its own job: `__cron_run.sh <job-name> -- ...`.
    # That name is authoritative, so take it verbatim and never re-derive it
    # from the command (which would resolve to the wrapper itself).
    if [[ "$cmd" == *__cron_run.sh* ]]; then
        job=$(sed -E 's/.*__cron_run\.sh[[:space:]]+([^[:space:]]+).*/\1/' <<<"$cmd")
    else
        # Unwrapped legacy line: name after its first real script, skipping
        # env assignments, sudo, and shell preamble.
        script=$(grep -oE '(/[^ ]+)?/[A-Za-z0-9_.-]+\.(sh|py)' <<<"$cmd" | head -1 || true)
        if [ -n "$script" ]; then
            job=$(basename "$script" | sed 's/\.[^.]*$//')
        else
            job=$(basename "$(awk '{for(i=1;i<=NF;i++) if ($i !~ /=/ && $i != "sudo") {print $i; exit}}' <<<"$cmd")")
        fi
        case "$cmd" in
            *--full*) job="${job}-full" ;;
            *--reconcile*) job="${job}-reconcile" ;;
        esac
        [[ "$line" == @reboot* ]] && job="${job}-reboot"
    fi
    [ -n "$job" ] || continue

    ts=""
    status_file="${STATE_DIR}/${job}.json"
    if [ -f "$status_file" ]; then
        ts=$(jq -r '.ts // empty' "$status_file" 2>/dev/null)
        state=$(jq -r '.state // "?"' "$status_file" 2>/dev/null)
        msg=$(jq -r '.message // ""' "$status_file" 2>/dev/null)
        last=$( [ -n "$ts" ] && human_age "$ts" || echo "unknown" )
    else
        # Fallback: last-write time of a redirected log, if the line has one.
        # No redirect is the common case, so a non-match must not abort the loop.
        logpath=$(grep -oE '>>?\s*[^ ]+\.log' <<<"$line" | awk '{print $NF}' | tail -1 || true)
        if [ -n "$logpath" ] && [ -f "${logpath/#\~/$HOME}" ]; then
            ts=$(stat -c %Y "${logpath/#\~/$HOME}" 2>/dev/null || echo "")
            last=$( [ -n "$ts" ] && human_age "$ts" || echo "unknown" )
            if [ -n "$ts" ] && [ "$(( $(date +%s) - ts ))" -gt "$(expected_interval "$schedule")" ]; then
                state="stale"
                msg="overdue: no output within its own schedule"
            else
                state="no-hit"
                msg="inferred from log mtime (not wrapped)"
            fi
        elif [[ "$cmd" == *__cron_run.sh* ]]; then
            # Wrapped but not yet run since; waiting, not unknowable.
            last="-"
            state="pending"
            msg="wrapped, awaiting first run"
        else
            last="unknown"
            state="?"
            msg="no wrapper data, no log redirect"
        fi
    fi

    printf '%-28s %-15s %-5s %-12s %s\n' "$job" "$schedule" "$(state_glyph "$state")" "$last" "$msg"
done

printf '\n%s\n' "Wrapper-reported jobs show real state (no-hit/hit/error). Everything else is a best-effort guess from log mtimes — route through __cron_run.sh to get real signal."
