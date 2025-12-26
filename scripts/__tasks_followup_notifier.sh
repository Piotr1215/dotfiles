#!/usr/bin/env bash

export DISPLAY=:1

# Get the list of task IDs where follow is set to Y
tasks=$(task follow.is:Y _ids)

# Check if the tasks list is not empty
if [ -n "$tasks" ]; then
	# Send the notification
	zenity --info --text "You have follow-up tasks to complete. Please check the task list."
fi
