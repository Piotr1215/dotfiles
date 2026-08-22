#!/usr/bin/env bash
# PROJECT: cron-manager
#
# Argos panel: registry + status for every locally scheduled cron job.
# Registry comes from crontab itself (can't drift). Status comes from
# ~/.local/state/cron-jobs/<job>.json where __cron_run.sh has been adopted;
# jobs not yet migrated show as "legacy" with a log-mtime guess instead.
#
# Click actions: view a job's log, or open the cron-manager tmuxinator
# session for a full diagnosis. Refresh: 1m (from filename suffix).

set -eo pipefail

STATE_DIR="${CRON_STATE_DIR:-$HOME/.local/state/cron-jobs}"
# Launch through alacritty explicitly: argos's own terminal=true picks
# x-terminal-emulator, which is not what this machine runs, and both actions
# end in a tmux attach that needs a real terminal.
INVESTIGATE="alacritty -e $HOME/dev/dotfiles/scripts/__cron_investigate.sh"
NEXT_RUN="$HOME/dev/dotfiles/scripts/__cron_next_run.py"
TRIGGER="alacritty -e $HOME/dev/dotfiles/scripts/__cron_trigger.sh"

# Argos renders every line as pango markup, so any bare `<`, `>` or `&` in a
# row aborts the parse and GNOME prints argos's own <span font_family=...>
# wrapper as literal text. The next-run column produces `<1m` for a job about
# to fire, which is exactly that case. Escape after padding, never before:
# `&lt;` is four bytes but one glyph, so column widths still line up.
#
# The backslashes are load-bearing: since bash 5.2 an unescaped `&` in the
# replacement half of ${var//pat/repl} means "the text that matched", so a
# plain `&lt;` expands to `<lt;` and escapes nothing.
esc() {
    local s="$1"
    s=${s//&/\&amp;}
    s=${s//</\&lt;}
    s=${s//>/\&gt;}
    printf '%s' "$s"
}

human_age() {
    local then="$1" now delta
    now=$(date +%s)
    delta=$(( now - then ))
    if   [ "$delta" -lt 3600 ]; then echo "$(( delta / 60 ))m"
    elif [ "$delta" -lt 86400 ]; then echo "$(( delta / 3600 ))h"
    else echo "$(( delta / 86400 ))d"
    fi
}

# Rough upper bound, in seconds, on how long a job may legitimately go quiet.
# Only precise enough to separate "ran on schedule" from "silently stopped" —
# healthchecks.io's dead-man's-switch idea, applied without a server.
expected_interval() {
    local sched="$1" min hour dom mon dow
    case "$sched" in
        @reboot) echo 2592000; return ;;      # only at boot; never call stale
        @daily|@midnight) echo 172800; return ;;
        @hourly) echo 7200; return ;;
        @weekly) echo 1209600; return ;;
        @monthly) echo 5184000; return ;;
    esac
    read -r min hour dom mon dow <<<"$sched"
    # Grace is 2x the nominal period, so one missed tick isn't an alarm.
    if [[ "$min" == */* ]]; then
        echo $(( ${min#*/} * 60 * 2 )); return
    fi
    if [[ "$min" == *,* ]]; then
        echo 7200; return                      # a few times an hour
    fi
    if [[ "$hour" == "*" ]]; then
        echo 7200; return                      # hourly at a fixed minute
    fi
    if [[ "$hour" == */* ]]; then
        echo $(( ${hour#*/} * 3600 * 2 )); return
    fi
    if [[ "$dow" != "*" || "$dom" != "*" || "$mon" != "*" ]]; then
        echo 1209600; return                   # weekly-or-rarer
    fi
    echo 172800                                # daily at a fixed time
}

# --- tally state across every job.json for the top-bar summary -------------
errors=0
hits=0
running=0
if [ -d "$STATE_DIR" ]; then
    for f in "$STATE_DIR"/*.json; do
        [ -f "$f" ] || continue
        read -r st pid < <(jq -r '[.state // "", .pid // ""] | @tsv' "$f" 2>/dev/null || echo "")
        case "$st" in
            error) errors=$(( errors + 1 )) ;;
            hit) hits=$(( hits + 1 )) ;;
            running)
                # A marker whose process is gone is a run that died before it
                # could write a result, not a live job. Without this the dot
                # would pulse forever after a single crash.
                if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                    running=$(( running + 1 ))
                fi
                ;;
        esac
    done
fi

# Not a clock/alarm glyph: the reminders widget already owns those in the bar.
icon="🗓"
if [ "$errors" -gt 0 ]; then
    color="#ff4444"; badge=" ${errors}!"
elif [ "$hits" -gt 0 ]; then
    color="#44ff44"; badge=" ${hits}★"
else
    color="#888888"; badge=""
fi

bar="<span color='${color}'>${icon}${badge}</span>"

if [ "$running" -gt 0 ]; then
    # Two button lines make argos alternate between them every 3s on its own
    # timer, without re-running this script (button.js: _cycleTimeout, which
    # only starts when buttonLines.length > 1). That is the whole pulse: a
    # dedicated fast-refreshing widget would have meant a second icon in the
    # bar, and refreshing this one every few seconds would re-parse the entire
    # crontab and close the job menu under the cursor on every tick.
    #
    # The dot says work is in flight; its colour says whether the last results
    # were clean. Red here does not mean the running job failed (it has not
    # finished), it means something else is already in the error state and is
    # worth looking at once this one lands.
    if [ "$errors" -gt 0 ]; then
        dot="🔴"
    else
        dot="🟢"
    fi

    # Self-colouring emoji rather than a <span color=...> around U+25CF: in the
    # panel that span rendered plain white, verified by screenshotting the bar.
    # An emoji carries its own colour and cannot be overridden by the panel
    # theme. Both glyphs are the same width, so nothing shifts as it blinks.
    # `dropdown=false` keeps the cycle lines out of the menu, which argos would
    # otherwise prepend them to.
    echo "${dot} ${bar} | font='monospace' size=11 dropdown=false"
    echo "⚫ ${bar} | font='monospace' size=11 dropdown=false"
else
    echo "${bar} | font='monospace' size=11"
fi
echo "---"
printf '<b>%s %-26s %-14s %-6s %s</b> | font=monospace\n' "  " "JOB" "SCHEDULE" "LAST" "NEXT"

# --- one row per registered job ---------------------------------------------
crontab -l 2>/dev/null | while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] && continue

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

    # Reset per row: a leaked $ts from the previous job would paint an
    # unknowable job green off someone else's timestamp.
    ts=""
    status_file="${STATE_DIR}/${job}.json"
    if [ -f "$status_file" ]; then
        state=$(jq -r '.state // "?"' "$status_file" 2>/dev/null)
        ts=$(jq -r '.ts // empty' "$status_file" 2>/dev/null)
        age=$( [ -n "$ts" ] && human_age "$ts" || echo "?" )
        log_path=$(jq -r '.log_path // ""' "$status_file" 2>/dev/null)
    else
        # No redirect is common; a non-match must not abort the loop.
        logpath_guess=$(grep -oE '>>?\s*[^ ]+\.log' <<<"$line" | awk '{print $NF}' | tail -1 || true)
        logpath_guess="${logpath_guess/#\~/$HOME}"
        if [ -n "$logpath_guess" ] && [ -f "$logpath_guess" ]; then
            ts=$(stat -c %Y "$logpath_guess" 2>/dev/null || echo "")
            age=$( [ -n "$ts" ] && human_age "$ts" || echo "?" )
            state="legacy"
            log_path="$logpath_guess"
        elif [[ "$cmd" == *__cron_run.sh* ]]; then
            # Wrapped but no state yet: it simply has not come round to its
            # next run since being wrapped. Waiting, not unknowable.
            state="pending"
            age="-"
            log_path=""
        else
            state="legacy"
            age="?"
            log_path="$logpath_guess"
        fi
    fi

    # Wrapper state is authoritative. Without it, fall back to staleness:
    # ran within its expected window = green, overdue = amber, unknowable = grey.
    case "$state" in
        error) glyph="🔴" ;;
        hit) glyph="🟢" ;;
        no-hit) glyph="🟢" ;;
        pending) glyph="🔵" ;;
        running)
            # A marker whose process is gone means the run died before it could
            # write a result, which is an error nobody would otherwise see.
            pid=$(jq -r '.pid // empty' "$status_file" 2>/dev/null)
            if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                glyph="🟣"; age="now"
            else
                glyph="🔴"; age="died"
            fi
            ;;
        *)
            if [ -n "$ts" ]; then
                budget=$(expected_interval "$schedule")
                if [ "$(( $(date +%s) - ts ))" -le "$budget" ]; then
                    glyph="🟢"
                else
                    glyph="🟠"
                fi
            else
                glyph="⚫"
            fi
            ;;
    esac

    # Strip the dotfiles' leading-underscore convention for display; the bar is
    # read at a glance and `__` is noise there.
    label="${job#__}"
    next=$(printf '%s\n' "$schedule" | "$NEXT_RUN" 2>/dev/null || echo "-")
    row=$(esc "$(printf '%s %-26s %-14s %-6s %s' "$glyph" "$label" "$schedule" "$age" "$next")")
    # One action for every row, whatever its state: hand the job to the
    # cron-manager agent. A log-only click would leave the unknowable jobs
    # (no redirect, no wrapper) with nothing to click at all.
    # A row with children renders as a menu in argos and its own action never
    # fires, so every job carries the same children rather than only the ones
    # holding a log. Clicking any job then behaves identically.
    echo "${row} | font=monospace"
    echo "--🔍 check status with agent | bash='${INVESTIGATE} \"${job}\"' terminal=false"
    echo "--▶ run now | bash='${TRIGGER} \"${job}\"' terminal=false"
    if [ -n "$log_path" ] && [ -f "$log_path" ]; then
        echo "--📄 open last run log | bash='alacritty -e nvim + \"${log_path}\"' terminal=false"
    else
        echo "--📄 no log yet | bash='true' terminal=false"
    fi
done

echo "---"
echo "🖥 Open cron-manager | bash='${INVESTIGATE}' terminal=false"
echo "Refresh now | refresh=true"
