#!/bin/bash

# Get the output from the task command
output=$(task tmark-next)

# Remove the header, footer lines, and any lines that are just dashes or empty
cleaned_output=$(echo "$output" | sed '1,2d;$d' | grep -vE '^[- ]*$')

# Process the cleaned output
declare -A tasks
while IFS= read -r line; do
	# Extract project and description
	project="${line%% *}"
	description="${line#* }"

	# Check if the line is empty (indicating a new project)
	if [ -z "$line" ]; then
		continue
	fi

	# Append to the tasks associative array
	tasks["$project"]+="- [ ] $description"$'\n'
done <<<"$cleaned_output"

# Print the tasks
for project in "${!tasks[@]}"; do
	echo "$project"
	echo -e "${tasks[$project]}"
done
