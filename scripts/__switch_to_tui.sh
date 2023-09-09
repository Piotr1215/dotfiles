#!/usr/bin/env bash

set -eo pipefail

# Capture the current session name
current_session=$(tmux display-message -p '#S')

# Parse the task description from the argument
TASK_DESCRIPTION="$1"

# Create a new tmux session named 'new-task-session' and run 'tui -r current'
tmux new-session -d -s new-task-session "tui -r current"

# Sleep for a bit to allow tui to load
sleep 0.1

# Send the keystrokes needed to filter tasks by description to the target pane
tmux send-keys -t new-task-session:1.1 "/description:$TASK_DESCRIPTION" C-m

# Attach to the new session
tmux switch-client -t new-task-session

# Wait for the session to be closed, either by the user or some other way
while tmux has-session -t new-task-session 2>/dev/null; do
	sleep 0.1
done

# Switch back to the original session
tmux switch-client -t $current_session
