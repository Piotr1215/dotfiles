#!/bin/bash

# Read the original and modified task JSON
read -r original_task
read -r modified_task

# Extract status and description from the modified task
status=$(echo "$modified_task" | jq -r '.status')
description=$(echo "$modified_task" | jq -r '.description')

# Check if the task is marked as completed
if [ "$status" == "completed" ]; then
	# Extract annotation and split it into line_number and file_path
	annotation=$(echo "$modified_task" | jq -r '.annotations[0].description // ""')
	regex="nvimline:([0-9]+):(.+)"
	if [[ $annotation =~ $regex ]]; then
		line_number="${BASH_REMATCH[1]}"
		file_path="${BASH_REMATCH[2]}"

		# Search and remove the line from the file
		if [ -f "$file_path" ]; then
			# Search for the line to remove based on the task description
			sed -i "/$description/d" "$file_path"
			zenity --info --text="Removed accompanying TODO in $file_path" --display=":1" \
				--ok-label="Acknowledged" --width=200 --height=100
		else
			echo "File $file_path does not exist" 1>&2
		fi
	else
		echo "No matching annotation found" 1>&2
	fi
fi

# Output the modified task JSON
echo "$modified_task"

# Status
exit 0
