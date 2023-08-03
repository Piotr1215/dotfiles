#!/bin/bash

# Function to list tasks based on status and project
list_tasks() {
	status="$1"
	project="$2"

	# Set the Taskwarrior filter based on the status
	filter=""
	mark=""
	if [ "$status" == "pending" ]; then
		filter="-COMPLETED"
		mark=" "
	else
		filter="+COMPLETED"
		mark="x"
	fi

	# Add the project filter if provided
	if [ -n "$project" ]; then
		filter+=" project:\"$project\""
	fi

	# Fetch tasks from Taskwarrior based on the filters
	task $filter export | jq -r ".[] | \"- [$mark] \" + .description"
}

# Default to pending tasks
status="pending"

# Check for the -c flag
if [ "$1" == "-c" ]; then
	status="completed"
	shift
fi

# Get the project name if provided
project="$1"

# Call the function to list tasks
list_tasks "$status" "$project"
