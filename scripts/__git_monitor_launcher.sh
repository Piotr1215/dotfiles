#!/usr/bin/env bash

# Check if we're being called from within a git-monitor session
CURRENT_SESSION=$(tmux display-message -p '#S')
if [[ "$CURRENT_SESSION" == git-monitor-* ]]; then
    # We're in a git-monitor session, check if we have a stored return session
    RETURN_SESSION_FILE="/tmp/tmux-git-monitor-return-${CURRENT_SESSION}"
    if [ -f "$RETURN_SESSION_FILE" ]; then
        RETURN_SESSION=$(cat "$RETURN_SESSION_FILE")
        if tmux has-session -t "$RETURN_SESSION" 2>/dev/null; then
            tmux switch-client -t "$RETURN_SESSION"
            exit 0
        fi
    fi
    # No valid return session, just display message
    tmux display-message "No return session found"
    exit 0
fi

# Normal flow - we're in a repository session
# Get the current pane's directory
CURRENT_DIR=$(tmux display-message -p '#{pane_current_path}')

# Find git root directory
GIT_ROOT=$(cd "$CURRENT_DIR" && git rev-parse --show-toplevel 2>/dev/null || echo "")

if [ -z "$GIT_ROOT" ]; then
    # Not in a git repository, do nothing
    exit 0
fi

# Get folder name from git root
FOLDER_NAME=$(basename "$GIT_ROOT")

# Create session name (replace periods with underscores for tmux compatibility)
SESSION_NAME="git-monitor-${FOLDER_NAME//./_}"

# Store the current session name for return
echo "$CURRENT_SESSION" > "/tmp/tmux-git-monitor-return-${SESSION_NAME}"

# Check if the session already exists
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    # Session exists, just switch to it
    tmux switch-client -t "$SESSION_NAME"
else
    # Session doesn't exist, create it
    # First, clean up any orphaned git-monitor sessions
    tmux kill-session -t "git-monitor" 2>/dev/null
    
    # Start new git-monitor session with dynamic name
    cd "$GIT_ROOT" && TMUXINATOR_SESSION_NAME="$SESSION_NAME" tmuxinator start git-monitor
fi