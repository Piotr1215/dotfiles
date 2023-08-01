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

# Check if a description was provided
if [ -z "$1" ]; then
	echo "Error: No task description provided."
	exit 1
fi

# Combine all arguments into the task description and wrap in quotes
description="\"$*\""

# Create the task and capture the output
output=$(task add $description +idea)

# Extract the task ID using grep and cut
task_id=$(echo "$output" | grep -o 'Created task [0-9]*.' | cut -d ' ' -f 3 | tr -d '.')

# Check the clipboard for a link
link=$(xclip -selection clipboard -o)

if [[ $link =~ ^https?:// ]]; then
	# Annotate the task with the link
	task $task_id annotate $link
fi

echo "Task created with ID: $task_id"
