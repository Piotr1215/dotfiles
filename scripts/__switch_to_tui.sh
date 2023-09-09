#!/usr/bin/env bash

# The set -e option instructs bash to immediately exit if any command has a non-zero exit status
# The set -u referencing a previously undefined  variable - with the exceptions of $* and $@ - is an error
# The set -o pipefail if any command in a pipeline fails, that return code will be used as the return code of the whole pipeline
set -eo pipefail

# Parse the task description from the argument
TASK_DESCRIPTION="$1"

# Create a new tmux session named 'new-task-session' and run 'tui -r current'
tmux new-session -d -s new-task-session "tui -r current"

# Sleep for a bit to allow tui to load
sleep 0.5

# Send the keystrokes needed to filter tasks by description to the target pane
tmux send-keys -t new-task-session:1.1 "/description:$TASK_DESCRIPTION" C-m

# Attach to the new session
tmux switch-client -t new-task-session
