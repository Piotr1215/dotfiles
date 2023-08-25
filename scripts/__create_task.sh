#!/usr/bin/env bash

# Source generic error handling funcion
source __trap.sh

# The set -e option instructs bash to immediately exit if any command has a non-zero exit status
# The set -u referencing a previously undefined  variable - with the exceptions of $* and $@ - is an error
# The set -o pipefaile if any command in a pipeline fails, that return code will be used as the return code of the whole pipeline
# https://bit.ly/37nFgin
set -eo pipefail

# Add source and line number wher running in debug mode: __run_with_xtrace.sh __create_task_idea.sh
# Set new line and tab for word splitting
IFS=$'\n\t'

help_function() {
	echo "Usage: __create_task_idea.sh <task_description> [labels] [project] [-h|--help]"
	echo ""
	echo "This script creates a new Taskwarrior task with the provided description, labels, and project."
	echo "If a valid URL is found in the clipboard, it annotates the task with the URL."
	echo ""
	echo "Options:"
	echo "  -h, --help    Show this help message and exit."
	echo ""
	echo "Arguments:"
	echo "  <task_description>    The description of the task to be created. Required."
	echo "  [labels]              Optional labels for the task (e.g., +idea, +work, +test)."
	echo "  [project]             Optional project for the task (e.g., project:on-call)."
	echo ""
	echo "Features:"
	echo "  - Creates a Taskwarrior task with the specified description, labels, and project."
	echo "  - Checks the clipboard for a valid URL and annotates the task with the URL if found."
	echo "  - Provides clear error handling and usage instructions."
	echo ""
	echo "Example:"
	echo "  __create_task_idea.sh \"this is a new task\" +idea +work project:on-call"
	echo ""
	echo "Note: The task is created with the Taskwarrior command-line tool."
}

# Check for help argument
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
	help_function
	exit 0
fi

# Check if a description was provided
if [ -z "$1" ]; then
	echo "Error: No task description provided."
	help_function
	exit 1
fi

# Combine all arguments into the task attributes
task_attributes="$*"

# Create the task and capture the output
output=$(task add $task_attributes)

# Extract the task ID using grep and cut
task_id=$(echo "$output" | grep -o 'Created task [0-9]*.' | cut -d ' ' -f 3 | tr -d '.')

# Check the clipboard for a link
link=$(xclip -selection clipboard -o)

if [[ $link =~ ^https?:// ]]; then
	# Annotate the task with the link
	task $task_id annotate $link
fi

echo "Task created with ID: $task_id"
