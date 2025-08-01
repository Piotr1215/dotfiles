#!/usr/bin/env bash

set -eo pipefail

# Check if in tmux first
if [ -z "$TMUX" ]; then
    echo "Error: This script must be run from within a tmux session"
    exit 1
fi

# Get current directory
CURRENT_DIR=$(tmux display-message -p '#{pane_current_path}')

# Use pet to search for a snippet
RESULT=$(pet search)

if [ -n "$RESULT" ]; then
    # Check if the command starts with xdg-open
    if [[ "$RESULT" =~ ^xdg-open[[:space:]] ]]; then
        # Execute xdg-open directly in current pane
        eval "$RESULT"
    else
        # Create a new vertical split pane for other commands
        tmux split-window -v -c "$CURRENT_DIR"
        
        # Get the new pane ID
        NEW_PANE=$(tmux display-message -p '#{pane_id}')
        
        # Clear the new pane
        tmux send-keys -t "$NEW_PANE" "clear" C-m
        
        # Check if command has parameters (contains ?)
        if [[ "$RESULT" =~ \? ]]; then
            # Send command without executing, so user can edit parameters
            tmux send-keys -t "$NEW_PANE" "$RESULT"
        else
            # Execute command directly
            tmux send-keys -t "$NEW_PANE" "$RESULT" C-m
        fi
        
        # Focus on the new pane
        tmux select-pane -t "$NEW_PANE"
    fi
fi