#!/usr/bin/env bash

# Get the current pane's directory
CURRENT_DIR=$(tmux display-message -p '#{pane_current_path}')

# Find git root directory
GIT_ROOT=$(cd "$CURRENT_DIR" && git rev-parse --show-toplevel 2>/dev/null || echo "")

if [ -z "$GIT_ROOT" ]; then
    tmux display-message "Error: Not in a git repository"
    exit 1
fi

# Get folder name from git root
FOLDER_NAME=$(basename "$GIT_ROOT")

# Create session name
SESSION_NAME="git-monitor-$FOLDER_NAME"

# Check if the session already exists
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    # Session exists, just switch to it
    tmux switch-client -t "$SESSION_NAME"
else
    # Session doesn't exist, create it
    # First, clean up any orphaned git-monitor sessions
    tmux kill-session -t "git-monitor" 2>/dev/null
    
    # Start new git-monitor session with dynamic name
    cd "$GIT_ROOT" && tmuxinator start git-monitor -n "$SESSION_NAME"
fi