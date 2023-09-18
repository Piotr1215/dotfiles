#!/usr/bin/env bash
uuid="$1"

# Fetch the current tags assigned to the task
current_labels=$(task _get $uuid.tags)

# Convert the labels to an array
IFS=',' read -ra label_array <<<"$current_labels"

# Initialize an additional filter condition
additional_filter=""

# Create the additional filter string, excluding the 'work' label
for label in "${label_array[@]}"; do
	if [ "$label" != "work" ]; then
		additional_filter="${additional_filter} +${label}"
	fi
done

# Define the command you want to run with Taskwarrior, in this case 'task current'

# Combine the command with the additional filter

# Execute the final command
task current +caas
