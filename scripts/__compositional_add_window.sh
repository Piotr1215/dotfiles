#!/usr/bin/env bash

set -eo pipefail

# Source the composite session manager
source /home/decoder/dev/dotfiles/scripts/__snippets_session_manager.sh

# Check if in tmux first
if [ -z "$TMUX" ]; then
    echo "Error: This script must be run from within a tmux session"
    exit 1
fi

# Get current session info
CURRENT_SESSION=$(get_current_session)
CURRENT_DIR=$(get_current_directory)

# Start with pet search as default
RESULT=$(pet search)

if [ -n "$RESULT" ]; then
    # Handle pet snippet result
    execute_in_composite "$CURRENT_SESSION" "$RESULT" "$CURRENT_DIR"
else
    # If pet search was cancelled, just switch to composite session
    switch_to_composite "$CURRENT_SESSION" "$CURRENT_DIR"
fi