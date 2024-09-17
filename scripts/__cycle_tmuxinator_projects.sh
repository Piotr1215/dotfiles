#!/bin/zsh

# Get the UUID of the selected task from the arguments
uuid="$@"

# Fetch the project of the task using Taskwarrior and jq
project=$(task "$uuid" export | jq -r '.[0].project')

# Check if the project is empty
if [[ -z "$project" || "$project" == "null" ]]; then
	echo "No project found for the selected task."
	# Optionally, reset the filter
	tmux send-keys "/" Escape
	tmux send-keys Escape
	tmux send-keys "/"
	tmux send-keys Enter
	exit 0
fi

# Escape any special characters in the project name
escaped_project=$(printf '%q' "$project")

# Send keys via tmux to apply the filter in taskwarrior-tui
tmux send-keys "/"
tmux send-keys Escape
tmux send-keys Escape
tmux send-keys "/"

# Use exact match in the filter to avoid partial matches
tmux send-keys "project.is:$escaped_project"
tmux send-keys Enter
