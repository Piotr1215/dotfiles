#!/usr/bin/env bash
# PROJECT: cron-manager
#
# The single click-action behind every row in the cron-status argos widget:
# open the cron-manager session and put one job in front of the agent.
#
# Uniform across states by design. A green job asks "show me what it did", a
# stale one asks "why did it stop", an error asks for a root cause, and an
# unknowable (black) one asks what it would take to get real signal. The
# agent decides which of those applies by reading the state itself, so the
# click means the same thing everywhere: investigate this job.
#
# Usage: __cron_investigate.sh <job-name>
#        __cron_investigate.sh              (no job: full sweep)
set -eo pipefail

SESSION="cron-manager"

job="${1:-}"

if [ -n "$job" ]; then
    directive="/ops-cron-manager show me the status of cron job '${job}'. Report what it is, when it last ran, when it runs next, and what its last run did. A click is a status check, not a bug report: most jobs are fine and 'this is healthy, nothing to do' is the expected answer. Only dig deeper if the state itself shows a problem (errored, or overdue against its own schedule), and say plainly when no action is needed."
else
    directive="/ops-cron-manager"
fi

# Reuse the session when it is already up; a second tmuxinator start would
# just attach anyway, and the agent pane there is already loaded.
# Type the directive, then submit it as a separate keystroke. Claude Code's
# prompt does not reliably accept a trailing C-m bundled into the same
# send-keys as a long line: the Enter lands while the paste is still settling
# and the directive sits in the prompt unsent.
send_directive() {
    local pane="$1"
    tmux set-option -p -t "${SESSION}:status.${pane}" @agent_injected_at "$(date +%s)" || return 1
    tmux send-keys -t "${SESSION}:status.${pane}" -l "$directive"
    sleep 0.4
    tmux set-option -p -t "${SESSION}:status.${pane}" @agent_injected_at "$(date +%s)" || return 1
    tmux send-keys -t "${SESSION}:status.${pane}" Enter
}

# Resolve the agent pane by what it is running rather than by index: this
# machine bases pane indices at 1, so a hardcoded index lands on the viddy
# dashboard and types the directive into a pager.
agent_pane() {
    tmux list-panes -t "${SESSION}:status" \
        -F '#{pane_index} #{pane_current_command}' 2>/dev/null |
        grep -v ' viddy$' | awk 'NR==1{print $1}'
}

# The tmux client Piotr typed in last, as "<name> <pid>": the Alacritty window
# in front of him. A panel click has no calling terminal, so recency is the
# signal, the same pick as focused_client_pane in __lib_pane_deliver.sh.
current_client() {
    tmux list-clients -F '#{client_activity} #{client_name} #{client_pid}' 2>/dev/null |
        sort -rn | awk 'NR==1{print $2, $3}'
}

# Raise the X window holding a tmux client. tmux only hands us the client's
# pid, and the window belongs to an ancestor (alacritty -> shell -> tmux), so
# walk up the parent chain until xdotool recognises one.
raise_client_window() {
    local pid="$1" win
    while [ -n "$pid" ] && [ "$pid" != 1 ]; do
        win=$(xdotool search --onlyvisible --pid "$pid" 2>/dev/null | head -1)
        if [ -n "$win" ]; then
            xdotool windowactivate "$win" 2>/dev/null
            return 0
        fi
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    done
}

# Put the session in the current Alacritty window: switch its tmux client and
# raise it. Piotr, 28 Nov 2026: "it should open new session in the current
# alacritty window". Raising whichever window was already attached left the
# agent behind his work in another window, and a detached session got a new
# window each time. A new window opens only when no tmux client exists at all;
# setsid so it outlives argos, which reaps the process group behind a bash=
# action as soon as it returns.
show_session() {
    local client pid
    if [ -n "$TMUX" ]; then
        tmux switch-client -t "$SESSION"
        return
    fi
    read -r client pid <<< "$(current_client)"
    if [ -z "$client" ]; then
        setsid alacritty -e tmux attach-session -t "$SESSION" >/dev/null 2>&1 &
        return
    fi
    tmux switch-client -c "$client" -t "$SESSION"
    raise_client_window "$pid"
}

# Start the session detached, so it can be shown in the current window rather
# than in the one tmuxinator would attach. The old code ran `tmuxinator start`
# in the foreground, which attaches and blocks, so a fresh session never
# received the job it was opened for.
started=0
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    tmuxinator start "$SESSION" --no-attach >/dev/null 2>&1 || true
    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
        notify-send "cron-manager" "the session did not start" 2>/dev/null || true
        exit 1
    fi
    started=1
fi

show_session

if [ -n "$job" ]; then
    # A fresh agent pane needs a moment before its prompt takes input.
    (( started )) && sleep "${CRON_INVESTIGATE_BOOT_WAIT:-3}"
    pane=$(agent_pane)
    [ -n "$pane" ] && send_directive "$pane"
fi
