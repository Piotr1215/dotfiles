#!/usr/bin/env bash

uuid="$1"

# Get the current priority of the task
current_priority=$(task _get $uuid.priority)

# Cycle through the priorities: H -> M -> L -> (unset) -> H
case $current_priority in
H)
	new_priority="M"
	echo "Switching priority from 'H' to 'M'"
	;;
M)
	new_priority="L"
	echo "Switching priority from 'M' to 'L'"
	;;
L)
	new_priority=""
	echo "Switching priority from 'L' to (no priority)"
	;;
"")
	new_priority="H"
	echo "Switching priority from (no priority) to 'H'"
	;;
esac

# Update the task with the new priority value, or remove priority if it's an empty string
if [ -n "$new_priority" ]; then
	echo "Updating task $uuid with new priority: $new_priority"
	task rc.bulk=0 rc.confirmation=off "$uuid" modify priority="$new_priority"
else
	echo "Removing priority from task $uuid"
	task rc.bulk=0 rc.confirmation=off "$uuid" modify priority:
fi
