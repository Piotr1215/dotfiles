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

if tmux has-session -t "$SESSION" 2>/dev/null; then
    if [ -n "$job" ]; then
        pane=$(agent_pane)
        [ -n "$pane" ] && send_directive "$pane"
    fi
    if [ -n "$TMUX" ]; then
        exec tmux switch-client -t "$SESSION"
    else
        exec tmux attach-session -t "$SESSION"
    fi
fi

tmuxinator start "$SESSION"

if [ -n "$job" ]; then
    # The agent pane needs to finish loading before it can take a directive.
    for _ in $(seq 1 20); do
        tmux has-session -t "$SESSION" 2>/dev/null && break
        sleep 0.5
    done
    sleep 3
    pane=$(agent_pane)
    [ -n "$pane" ] && send_directive "$pane"
fi
