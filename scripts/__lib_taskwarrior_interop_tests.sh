#!/bin/bash

# SAFETY: This test script uses +testonly_temp_deleteme tag
# NEVER change this to a tag used for real tasks!
# This prevents accidental deletion of production data

# Source the Taskwarrior interop script
source ./__lib_taskwarrior_interop.sh

# Helper function to clean up tasks created during testing
cleanup() {
	# Safety: Only delete tasks with our unique test tag
	local count=$(task +testonly_temp_deleteme count 2>/dev/null || echo 0)
	if [ "$count" -gt 0 ]; then
		task rc.confirmation=off +testonly_temp_deleteme delete
	fi
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

	task_id=$(create_task "$task_title" "+testonly_temp_deleteme")
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

	task_id=$(create_task "Complete test" "+testonly_temp_deleteme")
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
	# Use tomorrow as due date to ensure it's always valid
	due_date="tomorrow"

	task_id=$(create_task "$description" "+testonly_temp_deleteme" "due:$due_date")

	# Just check that due date exists (not empty)
	if task _get "$task_id".due 2>&1 | grep -qv "No matches"; then
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
	due_date="tomorrow"

	# Create task with due date
	task_id=$(create_task "$description" "+testonly_temp_deleteme" "due:$due_date")

	# Verify due date is set
	if task _get "$task_id".due 2>&1 | grep -q "No matches"; then
		report_failure "remove_due_date_setup" "Due date was not initially set."
	fi

	# Remove due date by setting due: without value
	task rc.confirmation=no "$task_id" modify due:

	# Verify due date is removed (should be empty)
	local due_after
	due_after=$(task _get "$task_id".due 2>/dev/null || echo "")
	if [[ -z "$due_after" ]]; then
		report_success "remove_due_date"
	else
		report_failure "remove_due_date" "Due date was not removed. Still shows: $due_after"
	fi

	cleanup
}

# Test get_task_id_by_description function
test_get_task_id_by_description() {
	local task_id retrieved_id
	local description="Test task for ID retrieval-$RANDOM"
	
	# Create task with github tag
	task_id=$(create_task "$description" "+github" "+testonly_temp_deleteme")
	
	# Try to retrieve it by description
	retrieved_id=$(get_task_id_by_description "$description")
	
	if [[ "$task_id" == "$retrieved_id" ]]; then
		report_success "get_task_id_by_description"
	else
		report_failure "get_task_id_by_description" "Retrieved ID ($retrieved_id) doesn't match created ID ($task_id)"
	fi
	
	cleanup
}

# Test special character handling in create_task
test_create_task_special_chars() {
	local task_id description
	description='Test "task" with $pecial & chars (brackets) [tags]'
	
	task_id=$(create_task "$description" "+testonly_temp_deleteme")
	
	# Verify the description was stored correctly
	local stored_desc
	stored_desc=$(task _get "$task_id".description)
	
	if [[ "$stored_desc" == "$description" ]]; then
		report_success "create_task_special_chars"
	else
		report_failure "create_task_special_chars" "Special characters not handled correctly"
	fi
	
	cleanup
}

# Test error handling for invalid operations
test_invalid_task_operations() {
	local invalid_uuid="00000000-0000-0000-0000-000000000000"
	
	# Test marking non-existent task as complete
	if mark_task_completed "$invalid_uuid" 2>/dev/null; then
		report_failure "invalid_task_operations" "Should fail for non-existent task"
	else
		report_success "invalid_task_operations_mark_completed"
	fi
	
	# Test annotating non-existent task
	if annotate_task "$invalid_uuid" "test annotation" 2>/dev/null; then
		report_failure "invalid_task_operations" "Should fail for non-existent task annotation"
	else
		report_success "invalid_task_operations_annotate"
	fi
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
sleep 2
test_get_task_id_by_description
sleep 2
test_create_task_special_chars
sleep 2
test_invalid_task_operations

# If all tests pass, exit with code 0
exit 0
