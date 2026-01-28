#!/usr/bin/env bash

# __lib_taskwarrior_interop.sh
# Interop functions for Taskwarrior

# Create a new task in Taskwarrior with a given description and optional additional attributes.
# Properly handle special characters in the description and other arguments.
create_task() {
	local description="$1"
	shift # Now $@ contains the rest of the arguments

	# Use an array to hold arguments to prevent word splitting
	local task_args=()
	for arg in "$@"; do
		task_args+=("$arg")
	done

	# Use -- to indicate end of options, and pass the description safely
	local output
	output=$(task add "${task_args[@]}" -- "$description")

	# Extract the UUID from the output using a reliable method
	local task_uuid
	task_uuid=$(echo "$output" | grep -Po '(?<=Created task )[a-z0-9\-]+')

	echo "$task_uuid"
}

# Get task UUID from description with specific tags (+github or linear_issue_id)
get_task_id_by_description() {
	local description="$1"
	# Use task export with tags +github or linear_issue_id.any: and status:pending to find the task by description
	# Return only the first UUID if multiple matches are found
	task '+github or linear_issue_id.any:' status:pending export |
		jq -r --arg desc "$description" '.[] | select(.description == $desc) | .uuid' |
		head -n 1
}

# Annotate an existing task
annotate_task() {
	local task_uuid="$1"
	local annotation="$2"
	task "$task_uuid" annotate -- "$annotation"
}

# Mark a task as completed
mark_task_completed() {
	local task_uuid="$1"
	echo "Attempting to mark task $task_uuid as completed..."
	task "$task_uuid" done || {
		echo "Failed to mark task $task_uuid as completed" >&2
		exit 1
	}
}

# Mark a task as pending
mark_task_pending() {
	local task_uuid="$1"
	task "$task_uuid" modify status:pending
}

# Get task labels (tags)
get_task_labels() {
	local task_uuid="$1"
	echo "Getting labels for task $task_uuid"
	task _get "$task_uuid".tags
}

# Add a label (tag) to a task
add_task_label() {
	local task_uuid="$1"
	local label="$2"

	# Get current task data
	local task_data=$(task rc.json.array=on "$task_uuid" export)

	# Add new tag to existing tags
	local updated_data=$(echo "$task_data" | jq --arg new_tag "$label" '.[0].tags += [$new_tag]')

	# Update task with new data
	echo "$updated_data" | task rc.json.array=on import >/dev/null 2>&1
}

# Remove a label (tag) from a task
remove_task_label() {
	local task_uuid="$1"
	local label="$2"
	task "$task_uuid" modify -"$label"
}

# Set or change a task's project
change_task_project() {
	local task_uuid="$1"
	local project_name="$2"
	task "$task_uuid" modify project:"$project_name"
}
