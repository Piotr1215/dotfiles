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
		filter="status:pending"
		mark=" "
	else
		filter="status:completed"
		mark="x"
	fi

	# If projects are provided, loop through each project and fetch tasks
	if [ ${#projects[@]} -gt 0 ]; then
		for project in "${projects[@]}"; do
			echo "$project"
			task rc.context=work "$filter" project:"$project" export 2>/dev/null | jq -r ".[] | \"- [$mark] \" + .description"
			echo
		done
	else
		# If no projects are provided, fetch tasks from all projects
		all_projects=($(task rc.context=work projects 2>/dev/null | grep -vE '^[0-9]+$' | grep -vE '^$' | tail -n +4 | head -n -2))
		for project in "${all_projects[@]}"; do
			tasks=$(task rc.context=work "$filter" project:"$project" export 2>/dev/null | jq -r ".[] | \"- [$mark] \" + .description")
			if [ -n "$tasks" ]; then
				echo "$project"
				echo "$tasks"
				echo
			fi
		done
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
