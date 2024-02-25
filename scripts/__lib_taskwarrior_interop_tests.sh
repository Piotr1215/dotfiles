#!/bin/bash

# Source the Taskwarrior interop script
source ./__lib_taskwarrior_interop.sh

# Helper function to clean up tasks created during testing
cleanup() {
	yes | task +integration delete
}

# Test creation of a new task and retrieval of its ID
test_create_task() {
	echo "Testing task creation..."
	local task_id
	local output

	output=$(create_task "Test task +integration")
	task_id=$(echo "$output" | grep -o '[0-9]*')
	if task _get "$task_id".description | grep -q "Test task"; then
		echo "Create task test passed."
	else
		echo "Create task test failed."
	fi
	cleanup
}

# Test annotation of an existing task
test_annotate_task() {
	echo "Testing task annotation..."
	local task_id
	local output

	output=$(create_task "Annotate test +integration")
	task_id=$(echo "$output" | grep -o '[0-9]*')
	annotate_task "$task_id" "Annotation text"
	if task _get "$task_id".annotations | grep -q "Annotation text"; then
		echo "Annotate task test passed."
	else
		echo "Annotate task test failed."
	fi
	cleanup
}

# Test marking a task as completed
test_mark_task_completed() {
	echo "Testing marking task as completed..."
	local task_id
	local output

	output=$(create_task "Complete test +integration")
	task_id=$(echo "$output" | grep -o '[0-9]*')
	mark_task_completed "$task_id"
	if task _get "$task_id".status | grep -q "completed"; then
		echo "Mark task completed test passed."
	else
		echo "Mark task completed test failed."
	fi
	cleanup
}

# Call test functions
test_create_task
test_annotate_task
test_mark_task_completed
