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

# Test creating a task with due date
test_task_with_due_date() {
	local task_id description due_date
	description="Task with due date"
	due_date="2025-07-15"

	task_id=$(create_task "$description" "+integration" "due:$due_date")

	if task _get "$task_id".due | grep -q "202507"; then
		report_success "create_task_with_due_date"
	else
		report_failure "create_task_with_due_date" "Due date was not set correctly."
	fi

	cleanup
}

# Test removing due date from a task
test_remove_due_date() {
	local task_id description due_date
	description="Task to remove due date"
	due_date="2025-07-15"

	# Create task with due date
	task_id=$(create_task "$description" "+integration" "due:$due_date")

	# Verify due date is set
	if ! task _get "$task_id".due | grep -q "202507"; then
		report_failure "remove_due_date_setup" "Due date was not initially set."
	fi

	# Remove due date by setting due: without value
	task rc.confirmation=no "$task_id" modify due:

	# Verify due date is removed
	if task _get "$task_id".due 2>&1 | grep -q "No matches"; then
		report_success "remove_due_date"
	else
		report_failure "remove_due_date" "Due date was not removed."
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
sleep 2
test_task_with_due_date
sleep 2
test_remove_due_date

# If all tests pass, exit with code 0
exit 0
