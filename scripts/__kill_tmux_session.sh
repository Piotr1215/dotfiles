#!/usr/bin/env bash
set -eo pipefail

# Get current session name
current_session=$(tmux display-message -p '#S' 2>/dev/null || echo "")

# List all sessions with current session first
{
    # Show current session first if we're in tmux
    if [ -n "$current_session" ]; then
        echo "$current_session"
    fi
    
    # Show all other sessions
    tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -v "^${current_session}$" || true
} | fzf --reverse --header="Kill Session (Current: ${current_session:-none})" | xargs -r tmux kill-session -t