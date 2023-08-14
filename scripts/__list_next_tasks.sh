#!/bin/bash
source __project_mappings.conf

# Get the output from the task command
output=$(task tmark-next)

# Remove the header, footer lines, and any lines that are just dashes or empty
cleaned_output=$(echo "$output" | sed '1,2d;$d' | grep -vE '^[- ]*$')

# Process the cleaned output
declare -A tasks
last_project=""
append_to_last=false

while IFS= read -r line; do
	# Extract project and description
	project="${line%% *}"
	description="${line#* }"

	# Trim leading spaces from the description
	description=$(echo "$description" | sed 's/^[ \t]*//')

	# If the project is not in the project_descriptions, it's a continuation line
	if [[ ! ${project_descriptions["$project"]} ]]; then
		project="$last_project"
		append_to_last=true
	else
		last_project="$project"
		append_to_last=false
	fi

	# Append to the tasks associative array
	if [ "$append_to_last" = true ]; then
		# Remove the last newline and append the continuation line
		tasks["$project"]="${tasks["$project"]%$'\n'} $description"$'\n'
	else
		tasks["$project"]+="- [ ] $description"$'\n'
	fi
done <<<"$cleaned_output"

# Print the tasks
for project in "${!tasks[@]}"; do
	echo "${project_descriptions[$project]:-$project}"
	echo -e "${tasks[$project]}"
done
