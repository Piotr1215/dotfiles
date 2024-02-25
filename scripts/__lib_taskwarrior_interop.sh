#!/bin/bash

# create_task
# Creates a new task in Taskwarrior with a given description and optional additional attributes.
#
# Usage:
#   task_id=$(create_task "Task Description" "+label1" "+label2" "project:ProjectName")
#
# Arguments:
#   $1 - The task description. This should be the first argument and in quotes if it contains spaces.
#   $@ - Optional additional arguments for the task, such as labels (prefixed with +) and project (prefixed with project:).
#       These should be separate arguments and not combined in a single string.
#
# Examples:
#   task_id=$(create_task "Review document" "+work" "project:Documentation")
#   This creates a task with the description "Review document", adds a "work" label, and assigns it to the "Documentation" project.
#
#   task_id=$(create_task "Fix bug in script" "+bugfix" "+urgent" "project:Development")
#   This creates a task with the description "Fix bug in script", adds "bugfix" and "urgent" labels, and assigns it to the "Development" project.
#
# Returns:
#   The ID of the newly created task.
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
