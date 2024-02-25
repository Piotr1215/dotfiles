#!/bin/bash

# Add a new task and return its ID
create_task() {
	# Combine all arguments into the task attributes
	local task_attributes="$*"

	local output task_id

	# shellcheck disable=SC2086 # Cannot quote $task_attributes as it is a list of arguments
	output=$(task add $task_attributes)
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
	# shellcheck disable=SC1010 # done in this case refers to the task status and not bash keyword
	task "$task_id" done
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
