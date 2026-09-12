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
# No terminal wrapper here: __cron_investigate.sh decides for itself whether to
# focus the window already attached to the cron-manager session or to open one.
# Wrapping it in `alacritty -e` made every click a new window.
INVESTIGATE="$HOME/dev/dotfiles/scripts/__cron_investigate.sh"
NEXT_RUN="$HOME/dev/dotfiles/scripts/__cron_next_run.py"
# No terminal for the trigger: it detaches the run and returns, and the widget
# is where the result shows up anyway. Paired with refresh=true on the menu
# item, argos re-reads state the moment the trigger exits, so the row flips to
# running immediately rather than at the next tick.
TRIGGER="$HOME/dev/dotfiles/scripts/__cron_trigger.sh"
# Clears a read `hit` off the badge. No terminal for the same reason as the
# trigger: it rewrites one state file and exits, and refresh=true on the menu
# item makes the star disappear on the click rather than a tick later.
ACK="$HOME/dev/dotfiles/scripts/__cron_ack.sh"
# Opens the crontab in nvim on the job's own line and installs the edit on
# save; the description line of every row is the click that gets there. A new
# tmux window in the session of the most recent client, the terminal in front
# of Piotr, same shape as the reminders applet: not alacritty (lands outside
# tmux) and not a popup (cannot stack on another). Absolute tmux path because
# argos runs outside the shell PATH. The window closes when nvim exits.
EDIT="$HOME/dev/dotfiles/scripts/__cron_edit.sh"
TMUX_BIN="/usr/local/bin/tmux"
# How long a hit keeps the star lit. A hit points at something already
# delivered (mail, a note, a log line), so its value expires: past a day the
# star is asking for attention that was either given or deliberately skipped,
# and either way it has stopped carrying information. The state on disk is
# untouched, so an expired hit is still readable in the job's row, its log and
# the status table -- only the badge stops counting it.
HIT_TTL="${CRON_HIT_TTL:-86400}"

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

# Parser and staleness budget are shared with __cron_status_dump.sh; see the
# lib for why they left this file.
# shellcheck source=/home/decoder/dev/dotfiles/scripts/__lib_cron_view.sh
source "$HOME/dev/dotfiles/scripts/__lib_cron_view.sh"

# --- one pass over the registry: a row per job, plus the tallies -----------
# The registry is the crontab, so a state file left behind by a deleted job
# cannot light the badge: it has no row, so it has no vote. (A hit from a
# retired reply-watcher held a star for hours that way.) Rows are buffered
# because argos wants the bar line first and the tallies are only known at
# the end.
errors=0
hits=0
overdue=0
running=0
rows=""
attention=""
now=$(date +%s)

while IFS=$'\t' read -r schedule job cmd purpose; do
    # Reset per row: a leaked $ts from the previous job would paint an
    # unknowable job green off someone else's timestamp.
    ts=""; msg=""; age="?"; log_path=""
    status_file="${STATE_DIR}/${job}.json"
    if [ -f "$status_file" ]; then
        IFS='|' read -r state ts pid msg < <(jq -r '[.state // "?", .ts // "", .pid // "", (.message // "" | gsub("\n"; " "))] | join("|")' "$status_file" 2>/dev/null || echo "?|||")
        [ -n "$ts" ] && age=$(human_age "$ts")
        log_path=$(jq -r '.log_path // ""' "$status_file" 2>/dev/null)
        # A `running` marker carries only {job, ts, state, pid}; the wrapper
        # adds log_path once the run finishes. The path is predictable, so
        # fall back to it; the existence check below still gates the menu.
        [ -z "$log_path" ] && log_path="${STATE_DIR}/${job}.log"
    else
        # No redirect is common; a non-match must not abort the loop.
        logpath_guess=$(grep -oE '>>?\s*[^ ]+\.log' <<<"$cmd" | awk '{print $NF}' | tail -1 || true)
        logpath_guess="${logpath_guess/#\~/$HOME}"
        if [ -n "$logpath_guess" ] && [ -f "$logpath_guess" ]; then
            ts=$(stat -c %Y "$logpath_guess" 2>/dev/null || echo "")
            [ -n "$ts" ] && age=$(human_age "$ts")
            state="legacy"
            log_path="$logpath_guess"
        elif [[ "$cmd" == *__cron_run.sh* ]]; then
            # Wrapped but no state yet: it has not come round to its next run
            # since being wrapped. Waiting, not unknowable.
            state="pending"
            age="-"
        else
            state="legacy"
        fi
    fi

    words=$(cron_human_schedule "$schedule" "$cmd")
    # Wrapper state is authoritative for the LAST run. Age is authoritative
    # for whether there has been one recently enough: a green result older
    # than the schedule allows is a job that stopped firing, and that is the
    # failure the wrapper cannot see because it never ran.
    case "$state" in
        error)
            glyph="🔴"; errors=$(( errors + 1 ))
            attention+="🔴 ${job#__} failed: ${msg:0:70}|${job}"$'\n'
            ;;
        hit|no-hit)
            if cron_spent "$msg"; then
                # Ran fine and told us its purpose is over: a tripped
                # verificator still on the schedule. Retire it.
                glyph="✅"; age="done"
                attention+="✅ ${job#__} has done its job, retire the line|${job}"$'\n'
            elif cron_overdue "$ts" "$schedule" "$cmd"; then
                glyph="🟠"; overdue=$(( overdue + 1 ))
                attention+="🟠 ${job#__} has not run for ${age} (${words})|${job}"$'\n'
            else
                glyph="🟢"
                # A hit older than the TTL stops counting. The star is latched
                # to the last exit code, so a MON,WED,FRI job would hold one
                # over the whole weekend and teach the badge to be ignored.
                if [ "$state" = "hit" ] && { [ -z "$ts" ] || [ $(( now - ts )) -le "$HIT_TTL" ]; }; then
                    hits=$(( hits + 1 ))
                fi
            fi
            ;;
        pending) glyph="🔵" ;;
        # Ran, then something took the machine out from under it. Amber, not
        # red: nothing is broken and there is nothing to fix, so it must not
        # read as "a cron job is fucked, spawn klod". Uncounted for the same
        # reason: the poweroff would summon attention every morning.
        interrupted) glyph="🟠" ;;
        running)
            # A marker whose process is gone is a run that died before it
            # could write a result, not a live job. A genuine hang still goes
            # red: `timeout --kill-after` sends SIGKILL and the wrapper
            # records 137 as error.
            if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                glyph="🟣"; age="now"; running=$(( running + 1 ))
            else
                glyph="🟠"; age="died"
                attention+="🟠 ${job#__} died mid-run (the nightly poweroff, usually); run it again|${job}"$'\n'
            fi
            ;;
        *)
            # Legacy: no wrapper, so staleness is the only signal there is.
            if [ -n "$ts" ]; then
                if cron_overdue "$ts" "$schedule" "$cmd"; then
                    glyph="🟠"; overdue=$(( overdue + 1 ))
                    attention+="🟠 ${job#__} has not run for ${age} (${words})|${job}"$'\n'
                else
                    glyph="🟢"
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
    # Purpose before schedule: "what is this" is the question a glance asks.
    # The row shows the first 54 characters; the full sentence is the first
    # line of the row's submenu, so a click reads the rest.
    short="$purpose"
    [ "${#short}" -gt 54 ] && short="${short:0:53}…"
    row=$(esc "$(printf '%s %-26s %-54s %-20s %-5s %s' "$glyph" "${label:0:26}" "$short" "$words" "$age" "$next")")
    # One action for every row, whatever its state: hand the job to the
    # cron-manager agent. A row with children renders as a menu in argos and
    # its own action never fires, so every job carries the same children.
    #
    # "run now" goes last on purpose: it used to sit directly above the log
    # item, the only entry that opens a window, so an imprecise or repeated
    # click ran the job and then opened nvim on its log.
    rows+="${row} | font=monospace"$'\n'
    rows+="--✎ $(esc "${purpose:-no description yet; click to add a comment line above the job}") | bash='${TMUX_BIN} new-window -n crontab \"${EDIT}\" \"${job}\"' terminal=false refresh=true"$'\n'
    rows+="--🔍 check status with agent | bash='${INVESTIGATE} \"${job}\"' terminal=false"$'\n'
    if [ -n "$log_path" ] && [ -f "$log_path" ]; then
        if [ "$state" = "running" ]; then
            rows+="--📄 follow live log | bash='alacritty -e nvim + \"${log_path}\"' terminal=false"$'\n'
        else
            rows+="--📄 open last run log | bash='alacritty -e nvim + \"${log_path}\"' terminal=false"$'\n'
        fi
    else
        rows+="--📄 no log yet | bash='true' terminal=false"$'\n'
    fi
    # Only a hit is ackable, and only while it is one. Errors get no such
    # entry on purpose (see __cron_ack.sh): red has to keep meaning "this
    # wants fixing".
    if [ "$state" = "hit" ]; then
        rows+="--★ mark as read | bash='${ACK} \"${job}\"' terminal=false refresh=true"$'\n'
    fi
    rows+="--▶ run now | bash='${TRIGGER} \"${job}\"' terminal=false refresh=true"$'\n'
done < <(cron_registry)

# --- the bar ----------------------------------------------------------------
# Not a clock/alarm glyph: the reminders widget already owns those in the bar.
# Red is an open fault and never expires. Amber is a job that stopped firing:
# nothing failed, so it is not red, but it is the failure that hides longest,
# so it is not silent either. Green is unread findings.
icon="🗓"
if [ "$errors" -gt 0 ]; then
    color="#ff4444"; badge=" ${errors}!"
elif [ "$overdue" -gt 0 ]; then
    color="#ffaa00"; badge=" ${overdue}⌛"
elif [ "$hits" -gt 0 ]; then
    color="#44ff44"; badge=" ${hits}★"
else
    color="#888888"; badge=""
fi
bar="<span color='${color}'>${icon}${badge}</span>"

if [ "$running" -gt 0 ]; then
    # Two button lines make argos alternate between them every 3s on its own
    # timer, without re-running this script (button.js: _cycleTimeout). That
    # is the whole pulse. The dot says work is in flight; its colour says
    # whether the last results were clean. Self-colouring emoji rather than a
    # <span color=...>: in the panel that span rendered plain white.
    if [ "$errors" -gt 0 ]; then dot="🔴"; else dot="🟢"; fi
    echo "${dot} ${bar} | font='monospace' size=11 dropdown=false"
    echo "⚫ ${bar} | font='monospace' size=11 dropdown=false"
else
    echo "${bar} | font='monospace' size=11"
fi
echo "---"
# What needs a person, in words, before the table. Each line is one click
# straight to the agent on that job; no submenu to open first. Nothing here
# means nothing needs doing, and the table below is only for the curious.
if [ -n "$attention" ]; then
    while IFS='|' read -r text job; do
        [ -n "$text" ] || continue
        echo "$(esc "$text") | bash='${INVESTIGATE} \"${job}\"' terminal=false"
    done <<<"$attention"
else
    echo "Nothing needs you. | color=#888888"
fi
echo "---"
printf '<b>%s %-26s %-54s %-20s %-5s %s</b> | font=monospace\n' "  " "JOB" "WHAT IT DOES" "SCHEDULE" "LAST" "NEXT"
printf '%s' "$rows"
echo "---"
echo "🖥 Open cron-manager | bash='${INVESTIGATE}' terminal=false"
echo "Refresh now | refresh=true"
