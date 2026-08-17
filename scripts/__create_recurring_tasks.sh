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

# Days the standup runs, as day-of-week numbers. Kept as a variable because the
# schedule is the bot's to change, not this script's to encode: the old Mon/Wed/
# Fri cadence lived in three hardcoded case arms and removing it took a commit.
standup_days="${STANDUP_DAYS:-1 2 3 4 5}"

# Get the day of the week (1-7, where 1 is Monday)
day_of_week=$(date +%u)

# Get the day of the month (1-31)
day_of_month=$(date +%d)

# Function to check if today is the first working day of the month
is_first_working_day() {
	local current_day=$1
	local current_dow=$2
	
	# If it's the 1st and a weekday, it's the first working day
	if [ "$current_day" -eq 1 ] && [ "$current_dow" -le 5 ]; then
		return 0
	fi
	
	# If it's the 2nd and Monday (meaning 1st was Sunday)
	if [ "$current_day" -eq 2 ] && [ "$current_dow" -eq 1 ]; then
		return 0
	fi
	
	# If it's the 3rd and Monday (meaning 1st was Saturday, 2nd was Sunday)
	if [ "$current_day" -eq 3 ] && [ "$current_dow" -eq 1 ]; then
		return 0
	fi
	
	return 1
}

# Only run daily tasks on weekdays (1-5)
if [ "$day_of_week" -le 5 ]; then
	# Daily tasks (weekdays only)
	add_task_if_not_exists "fill daily hours" "today+8h"
	add_task_if_not_exists "check notifications" "today+8h"
	add_task_if_not_exists "respond to slack messages" "today+8h"

	# Day-specific tasks
	if [[ " $standup_days " == *" $day_of_week "* ]]; then
		# session:standup is what makes this more than a reminder: the
		# on-modify-tmuxinator hook in ~/.task/hooks reads it on start and
		# opens the session that renders the answers.
		add_task_if_not_exists "fill standup" "today+8h" "session:standup"
	fi

	case $day_of_week in
	4) # Thursday
		add_task_if_not_exists "fill eng presentation" "today+8h"
		;;
	esac
	echo "Daily task check complete."
else
	echo "Weekend - no tasks added."
fi
