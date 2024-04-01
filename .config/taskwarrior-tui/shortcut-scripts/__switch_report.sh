#!/usr/bin/env bash

marker_file="$HOME/.task_context_switch"

switch_context() {
	task context "$1"
	echo "Switched to $1 context."
}

# Get the current task context
current_context=$(task _get rc.context)

# Check if the current context is "work"
if [ "$current_context" == "work" ]; then
	switch_context home
	# Set the marker file to indicate we should switch back to work next time
	echo "work" >"$marker_file"
elif [ "$current_context" == "home" ] && [ -f "$marker_file" ]; then
	# If we're in home and the marker file exists, it means we want to switch back to work
	switch_context work
	# Remove the marker file after switching back to avoid repeated switches
	rm "$marker_file"
else
	echo "Current context is: $current_context. No action taken."
fi
