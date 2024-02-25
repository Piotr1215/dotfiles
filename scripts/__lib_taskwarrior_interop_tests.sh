#!/bin/bash

# Source the Taskwarrior interop script
source ./__lib_taskwarrior_interop.sh

# Helper function to clean up tasks created during testing
cleanup() {
	yes | task +integration delete
}

# Helper function to report a test failure
report_failure() {
	echo "Test failed: $1 - $2"
	exit 1
}

# Helper function to report a test success
report_success() {
	echo "Test succeeded: $1"
}

# Test creation of a new task and retrieval of its ID
test_create_task() {
	local task_id description label
	description="Test task"
	label="integration"

	task_id=$(create_task "$description" "+$label")

	if task _get "$task_id".description | grep -q "$description"; then
		report_success "create_task"
	else
		report_failure "create_task" "Description does not match."
	fi

	if task _get "$task_id".tags | grep -q "$label"; then
		report_success "label_assignment"
	else
		report_failure "label_assignment" "Label was not added."
	fi

	cleanup
}

# Test annotation of an existing task
test_annotate_task() {
	local task_id annotation
	local task_title="Annotate test-$RANDOM"
	annotation="Annotation text"

	task_id=$(create_task "$task_title" "+integration")
	annotate_task "$task_id" "$annotation"

	# Adjusted to check for the description of the first annotation
	if task _get "$task_id".annotations.1.description | grep -q "$annotation"; then
		report_success "annotate_task"
	else
		report_failure "annotate_task" "Annotation was not added."
	fi

	cleanup
}

# Test marking a task as completed
test_mark_task_completed() {
	local task_id

	task_id=$(create_task "Complete test" "+integration")
	mark_task_completed "$task_id"

	if task _get "$task_id".status | grep -q "completed"; then
		report_success "mark_task_completed"
	else
		report_failure "mark_task_completed" "Task was not marked completed."
	fi

	cleanup
}

cleanup
sleep 2
test_create_task
sleep 2
test_annotate_task
sleep 2
test_mark_task_completed

# If all tests pass, exit with code 0
exit 0
