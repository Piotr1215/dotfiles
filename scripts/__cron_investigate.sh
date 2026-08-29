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
    tmux send-keys -t "${SESSION}:status.${pane}" -l "$directive"
    sleep 0.4
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

# Raise the terminal that is already attached to the session rather than
# opening a second one. Every click used to run `alacritty -e ...`, so a
# click was unconditionally a new window: the old one stayed attached to the
# same session and the desktop filled up with duplicates. tmux only hands us
# the client's pid (the tmux client process), and the X window belongs to an
# ancestor of it (alacritty -> shell -> tmux), so walk up the parent chain
# until xdotool recognises one.
focus_attached_client() {
    local pid win
    pid=$(tmux list-clients -t "$SESSION" -F '#{client_pid}' 2>/dev/null | head -1)
    [ -n "$pid" ] || return 1
    while [ -n "$pid" ] && [ "$pid" != 1 ]; do
        win=$(xdotool search --onlyvisible --pid "$pid" 2>/dev/null | head -1)
        if [ -n "$win" ]; then
            xdotool windowactivate "$win" 2>/dev/null && return 0
            return 1
        fi
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    done
    return 1
}

# setsid so the window outlives argos, which reaps the process group behind a
# bash= action as soon as it returns.
spawn_terminal() {
    if tmux has-session -t "$SESSION" 2>/dev/null; then
        setsid alacritty -e tmux attach-session -t "$SESSION" >/dev/null 2>&1 &
    else
        setsid alacritty -e tmuxinator start "$SESSION" >/dev/null 2>&1 &
    fi
}

if tmux has-session -t "$SESSION" 2>/dev/null; then
    if [ -n "$job" ]; then
        pane=$(agent_pane)
        [ -n "$pane" ] && send_directive "$pane"
    fi
    # Already inside tmux: the caller has a terminal, just move it.
    if [ -n "$TMUX" ]; then
        exec tmux switch-client -t "$SESSION"
    fi
    # A window is already showing this session: focus it and stop. Only when
    # the session is detached (every terminal closed) do we need a new one.
    focus_attached_client && exit 0
    spawn_terminal
    exit 0
fi

# No session at all. Start it inside its own window, then wait for the agent
# pane before typing. The old code ran `tmuxinator start` in the foreground,
# which attaches and blocks, so the directive below was only ever sent after
# the user detached: a fresh session never received the job it was opened for.
spawn_terminal

if [ -n "$job" ]; then
    for _ in $(seq 1 40); do
        tmux has-session -t "$SESSION" 2>/dev/null && break
        sleep 0.5
    done
    sleep 3
    pane=$(agent_pane)
    [ -n "$pane" ] && send_directive "$pane"
fi
