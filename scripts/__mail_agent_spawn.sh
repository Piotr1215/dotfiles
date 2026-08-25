#!/usr/bin/env bash
# PROJECT: mail-agent
#
# Put a work mail thread in front of ursula, the work appointments and mail
# assistant, and raise her pane.
#
# The sibling of __cron_investigate.sh: same reuse-the-session-first rules,
# same resolve-the-pane-by-what-it-runs rule, same type-then-Enter-separately
# rule. One difference that matters: the tmuxinator mail session already boots
# that pane into /ops-mail-agent, so the directive sent here is a plain
# instruction, never the slash command. Sending the slash command to a live
# agent would restart her whole startup sweep instead of answering the mail.
#
# Usage: __mail_agent_spawn.sh <thread-id>   act on one thread
#        __mail_agent_spawn.sh              just raise her pane
set -eo pipefail

SESSION="mail"
WINDOW="ursula"
TARGET="${SESSION}:${WINDOW}"

# What ursula is asked to do with the thread. Kept as a function so the
# wording is testable: the "do not send" half is the whole safety contract of
# handing mail to an agent, and a silent edit to it should fail a test.
build_directive() {
    local t="${1:-}"
    t="${t#thread:}"
    [ -n "$t" ] || return 0
    printf 'Work mail thread:%s in the local notmuch db. Read it, tell me what it says and what it wants from me, and draft the reply. Preview the draft, do not send it.' "$t"
}

# Resolve the agent pane by finding the claude process under it. The ursula
# window also carries a viddy monitor and a tmuxinator artifact pane, and pane
# indices are 1-based on this machine, so anything positional lands on the
# wrong one and types the directive into a pager.
#
# Match the process name exactly rather than searching command lines. A
# `pgrep -f claude` also matches __claude_with_monitor.sh,
# __claude_prompt_monitor.sh, __nats_watcher.sh and a dashboard injector, all
# of which are live on this box. Today the ancestry walk below still lands on
# the right pane, but the day this window gains a second claude-ish process the
# failure mode is a directive typed into the wrong pane, not an error. `-x`
# matches only the agent REPL itself.
pane_owns_pid() {
    local pane_pid="$1" proc="$2" ancestor="$2"
    while [ -n "$ancestor" ] && [ "$ancestor" != 1 ]; do
        [ "$ancestor" = "$pane_pid" ] && return 0
        ancestor=$(ps -o ppid= -p "$ancestor" 2>/dev/null | tr -d ' ')
    done
    return 1
}

agent_pane_matching() {
    local -a candidates
    mapfile -t candidates < <("$@" 2>/dev/null)
    [ ${#candidates[@]} -gt 0 ] || return 1

    local idx pid proc
    while read -r idx pid; do
        [ -n "$idx" ] || continue
        for proc in "${candidates[@]}"; do
            if pane_owns_pid "$pid" "$proc"; then
                printf '%s' "$idx"
                return 0
            fi
        done
    done < <(tmux list-panes -t "$TARGET" -F '#{pane_index} #{pane_pid}' 2>/dev/null)
    return 1
}

# Exact match only, with no loose fallback. A fallback was tried and removed:
# with a decoy pane running __claude_prompt_monitor_decoy.sh ahead of the real
# agent, `pgrep -f claude` resolved to the decoy and the directive was typed
# into it. Delivering nothing is a visible failure, Piotr's pane simply does
# not answer. Delivering into the wrong pane is not.
agent_pane() {
    agent_pane_matching pgrep -x claude
}

# Type the directive, then submit it as a separate keystroke. Claude Code's
# prompt drops a C-m bundled into the same send-keys as a long line: the Enter
# lands while the paste is still settling and the directive sits unsent.
send_directive() {
    local pane="$1"
    [ -n "$directive" ] || return 0
    tmux send-keys -t "${TARGET}.${pane}" -l "$directive"
    sleep 0.4
    tmux send-keys -t "${TARGET}.${pane}" Enter
}

# Raise the terminal already attached to the session rather than opening a
# second one, walking up from the tmux client pid until xdotool recognises an
# ancestor (alacritty -> shell -> tmux).
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

# setsid so the window outlives whatever launched this (an fzf popup that is
# already aborting, or an argos action being reaped).
spawn_terminal() {
    if tmux has-session -t "$SESSION" 2>/dev/null; then
        setsid alacritty -e tmux attach-session -t "$SESSION" >/dev/null 2>&1 &
    else
        setsid alacritty -e tmuxinator start "$SESSION" >/dev/null 2>&1 &
    fi
}

main() {
    local thread="${1:-}" pane here
    directive=$(build_directive "$thread")

if tmux has-session -t "$SESSION" 2>/dev/null; then
    pane=$(agent_pane) || pane=""

    # Never type into the pane that called this. Asking ursula to act on a
    # thread from inside her own pane would echo the directive into whatever
    # she is already doing.
    here=$(tmux display-message -p '#{session_name}:#{window_name}.#{pane_index}' 2>/dev/null || true)
    if [ -n "$pane" ] && [ "$here" != "${TARGET}.${pane}" ]; then
        send_directive "$pane"
    fi

    if [ -n "$TMUX" ]; then
        tmux select-window -t "$TARGET" 2>/dev/null || true
        [ -n "$pane" ] && tmux select-pane -t "${TARGET}.${pane}" 2>/dev/null
        exec tmux switch-client -t "$SESSION"
    fi

    tmux select-window -t "$TARGET" 2>/dev/null || true
    focus_attached_client && exit 0
    spawn_terminal
    exit 0
fi

# No session at all. Start it, then wait for the agent to come up before
# typing: a directive sent into a pane that is still booting is lost.
spawn_terminal

if [ -n "$directive" ]; then
    for _ in $(seq 1 40); do
        tmux has-session -t "$SESSION" 2>/dev/null && break
        sleep 0.5
    done
    for _ in $(seq 1 30); do
        pane=$(agent_pane) && [ -n "$pane" ] && break
        sleep 1
    done
    [ -n "${pane:-}" ] && send_directive "$pane"
fi
}

# Sourcing runs nothing, so the directive wording can be tested without a live
# tmux server.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
