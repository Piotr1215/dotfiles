#!/bin/bash

# Function to list tasks based on status and projects
list_tasks() {
	status="$1"
	shift
	projects=("$@")

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

	# If projects are provided, loop through each project and fetch tasks
	if [ ${#projects[@]} -gt 0 ]; then
		for project in "${projects[@]}"; do
			echo "$project"
			task $filter project:"$project" export | jq -r ".[] | \"- [$mark] \" + .description"
			echo
		done
	else
		# If no projects are provided, fetch tasks from all projects
		task $filter export | jq -r ".[] | \"- [$mark] \" + .description"
	fi
}

# Default to pending tasks
status="pending"

# Check for the -c flag
if [ "$1" == "-c" ]; then
	status="completed"
	shift
fi

# Call the function to list tasks
list_tasks "$status" "$@"
