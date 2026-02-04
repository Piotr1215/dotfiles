#!/usr/bin/env bash

export DISPLAY=:0

# Get the current time and the time in one hour
now=$(date +%s)
in_one_hour=$(date -d "+1 hour" +%s)

# Get a list of tasks due today
tasks_due_today=$(task due:today _ids)

# Initialize an empty string to hold tasks due within the next hour
tasks_due_soon=""

for task_id in $tasks_due_today; do
	# Get the due date of the task in epoch time
	task_due_date=$(task _get $task_id.due)
	task_due_epoch=$(date -d "$task_due_date" +%s)
	task_description=$(task _get $task_id.description)

	# Check if the task is due within the next hour
	if [ "$task_due_epoch" -gt "$now" ] && [ "$task_due_epoch" -le "$in_one_hour" ]; then
		tasks_due_soon+="- $task_id: $task_description\n "
	fi
done

# Check if the tasks_due_soon string is not empty
if [ -n "$tasks_due_soon" ]; then
	# Send the notification
	zenity --info --text "You have tasks due in the next hour:\n $tasks_due_soon"
fi
