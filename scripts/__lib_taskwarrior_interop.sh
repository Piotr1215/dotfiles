#!/bin/bash

# Add a new task and return its ID
create_task() {
	local description=$1
	shift # Now $@ contains the rest of the arguments

	# Use "$@" to pass all additional arguments to task add
	local output
	output=$(task add "$description" "$@")
	local task_id
	task_id=$(echo "$output" | grep -o 'Created task [0-9]*.' | cut -d ' ' -f 3 | tr -d '.')
	echo "$task_id"
}

# Annotate an existing task
annotate_task() {
	local task_id="$1"
	local annotation="$2"
	task "$task_id" annotate "$annotation"
}

# Mark a task as completed
mark_task_completed() {
	local task_id="$1"
	echo "Attempting to mark task $task_id as completed..."
	#shellcheck disable=SC1010
	task "$task_id" done || {
		echo "Failed to mark task $task_id as completed"
		exit 1
	}
}

# Mark a task as pending
mark_task_pending() {
	local task_id="$1"
	task "$task_id" modify status:pending
}

# Add a label to a task
add_task_label() {
	local task_id="$1"
	local label="$2"
	task "$task_id" modify +"$label"
}

# Remove a label from a task
remove_task_label() {
	local task_id="$1"
	local label="$2"
	task "$task_id" modify -"$label"
}

# Set or change a task's project
change_task_project() {
	local task_id="$1"
	local project_name="$2"
	task "$task_id" modify project:"$project_name"
}
