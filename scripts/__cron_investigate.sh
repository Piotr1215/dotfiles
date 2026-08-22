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
    directive="/ops-cron-manager investigate the single cron job '${job}'. Resolve its current state first, then act on what that state calls for: recent output if it is healthy, why it stopped if it is overdue, a root cause if it errored, or what it would take to get real signal if its state is unknowable. Report the finding and the one action worth taking."
else
    directive="/ops-cron-manager"
fi

# Reuse the session when it is already up; a second tmuxinator start would
# just attach anyway, and the agent pane there is already loaded.
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
        [ -n "$pane" ] && tmux send-keys -t "${SESSION}:status.${pane}" "$directive" C-m
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
    [ -n "$pane" ] && tmux send-keys -t "${SESSION}:status.${pane}" "$directive" C-m
fi
