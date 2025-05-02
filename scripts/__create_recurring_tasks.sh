#!/usr/bin/env bash
set -eo pipefail

# Set new line and tab for word splitting
IFS=$'\n\t'

# Function to add a task if it doesn't exist for today (either pending or completed)
add_task_if_not_exists() {
	local task_description="$1"
	local due_time="$2"
	local session="$3"

	# Check for pending tasks due today
	if ! task project:admin description.is:"$task_description" due:today status:pending count | grep -q '1' &&
		! task project:admin description.is:"$task_description" due:today status:completed count | grep -q '1'; then
		if [ -n "$session" ]; then
			task add project:admin tags:work,kill due:"$due_time" "$task_description" "$session"
		else
			task add project:admin tags:work due:"$due_time" "$task_description"
		fi
		echo "Added task: $task_description"
	else
		echo "Task already exists or was completed for today: $task_description"
	fi
}

# Get the day of the week (1-7, where 1 is Monday)
day_of_week=$(date +%u)

# Get the day of the month (1-31)
day_of_month=$(date +%d)

# Check if it's the 1st of the month and add monthly task
if [ "$day_of_month" -eq 1 ]; then
	add_task_if_not_exists "cleanup hosted platform instances" "today+8h" "session:vcluster-prod"
	echo "Monthly task check complete."
fi

# Only run daily tasks on weekdays (1-5)
if [ "$day_of_week" -le 5 ]; then
	# Daily tasks (weekdays only)
	add_task_if_not_exists "fill daily hours" "today+8h"
	add_task_if_not_exists "check github notifications" "today+8h"
	add_task_if_not_exists "respond to slack messages" "today+8h"

	# Day-specific tasks
	case $day_of_week in
	1) # Monday
		add_task_if_not_exists "fill standup forms" "today+8h" "session:standup"
		;;
	3) # Wednesday
		add_task_if_not_exists "fill standup forms" "today+8h" "session:standup"
		;;
	4) # Thursday
		add_task_if_not_exists "fill eng presentation" "today+8h"
		;;
	5) # Friday
		add_task_if_not_exists "fill standup forms" "today+8h" "session:standup"
		;;
	esac
	echo "Daily task check complete."
else
	echo "Weekend - no tasks added."
fi