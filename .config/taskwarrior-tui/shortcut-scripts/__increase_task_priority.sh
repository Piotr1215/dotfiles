#!/usr/bin/env bash
uuid="$1"
current_priority=$(task _get $uuid.manual_priority)

# Check if manual_priority is set, if not, initialize to 0
if [ -z "$current_priority" ]; then
	current_priority=0
fi

# Increment the priority
new_priority=$((current_priority + 1))

# Update the task with the new manual_priority value
task rc.bulk=0 rc.confirmation=off $uuid modify manual_priority=$new_priority
