#!/usr/bin/env bash

# This script switches to existing git-monitor session
# First tries to find one for current git repo, then any existing git-monitor session

# Get the current pane's directory
CURRENT_DIR=$(tmux display-message -p '#{pane_current_path}')

# Find git root directory
GIT_ROOT=$(cd "$CURRENT_DIR" && git rev-parse --show-toplevel 2>/dev/null || echo "")

if [ -n "$GIT_ROOT" ]; then
    # We're in a git repo, try to find specific git-monitor session
    FOLDER_NAME=$(basename "$GIT_ROOT")
    SESSION_NAME="git-monitor-$FOLDER_NAME"
    
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        tmux switch-client -t "$SESSION_NAME"
        exit 0
    fi
fi

# Not in a git repo OR no specific session exists
# Try to find ANY git-monitor session
EXISTING_SESSION=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "^git-monitor-" | head -1)

if [ -n "$EXISTING_SESSION" ]; then
    tmux switch-client -t "$EXISTING_SESSION"
fi