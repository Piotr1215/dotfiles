#!/usr/bin/env bash

set -eo pipefail

# Add source and line number wher running in debug mode: __run_with_xtrace.sh __create_recurring_tasks.sh
# Set new line and tab for word splitting
IFS=$'\n\t'

# Function to add a task if it doesn't exist for today
add_task_if_not_exists() {
	local task_description="$1"
	local due_time="$2"
	local session="$3"

	# Check if the task already exists for today
	if ! task project:admin "$task_description" due:today status:pending count | grep -q '1'; then
		# Task doesn't exist, so add it
		if [ -n "$session" ]; then
			task add project:admin tags:work,kill due:"$due_time" "$task_description" "$session"
		else
			task add project:admin tags:work due:"$due_time" "$task_description"
		fi
		echo "Added task: $task_description"
	else
		echo "Task already exists for today: $task_description"
	fi
}

# Daily tasks
add_task_if_not_exists "fill daily hours" "today+8h"
add_task_if_not_exists "check github notifications" "today+8h"
add_task_if_not_exists "respond to slack messages" "today+8h"

# Check the day of the week and add specific tasks
day_of_week=$(date +%u)

case $day_of_week in
1) # Monday
	add_task_if_not_exists "fill standup forms" "today+8h" "session:standup"
	add_task_if_not_exists "meeting with denise" "today+8h"
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
