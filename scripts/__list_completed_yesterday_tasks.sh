#!/bin/bash
source __project_mappings.conf

# Get the output from the task command
output=$(task tmark-yesterday)

# Remove the header, footer lines, and any lines that are just dashes or empty
cleaned_output=$(echo "$output" | sed '1,2d;$d' | grep -vE '^[- ]*$')

# Process the cleaned output
declare -A tasks
while IFS= read -r line; do
	# Extract project and description
	project="${line%% *}"
	description="${line#* }"

	# Trim leading and trailing spaces or tabs from the project and description
	project=$(echo "$project" | sed 's/^[ \t]*//;s/[ \t]*$//')
	description=$(echo "$description" | sed 's/^[ \t]*//;s/[ \t]*$//')

	# If project is empty after trimming, assign a default value
	if [ -z "$project" ]; then
		project="None"
	fi

	# Append to the tasks associative array
	tasks["$project"]+="- [x] $description"$'\n'
done <<<"$cleaned_output"

# Print the tasks
for project in "${!tasks[@]}"; do
	echo "${project_descriptions[$project]:-$project}"
	echo -e "${tasks[$project]}"
done
