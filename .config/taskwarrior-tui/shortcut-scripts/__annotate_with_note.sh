#!/usr/bin/env bash

# UUID of the task to annotate
uuid="$@"

# Base directory where notes are stored
notes_dir="/home/decoder/dev/obsidian/decoder/Notes/"

# Array of subdirectories to search in
subdirs=("areas" "meetings" "projects" "resources" "reviews")

# Find files in the specified subdirectories and show fzf dialog to select an existing note
filepath=$(find "${subdirs[@]/#/$notes_dir}" -type f -name '*.md' | fzf-tmux --preview "bat --color=always {}")

# If fzf was cancelled, exit the script
if [ -z "$filepath" ]; then
	echo "No file selected. Exiting."
	exit 1
fi

# Annotate the task with the selected filepath
task_output=$(task rc.bulk=0 rc.confirmation=off "$uuid" annotate "$filepath")

# Check if annotation was successful
if [[ "$task_output" == *"Annotated"* ]]; then
	echo "Successfully annotated the task with the note."
else
	echo "Failed to annotate the task."
fi

# Open the selected note in nvim
nvim "$filepath"
