#!/bin/bash

# List all subdirectories in ~/loft but exclude ~/loft itself
selected_folder=$(find ~/loft -mindepth 1 -maxdepth 1 -type d | sed 's|.*/||' | fzf --prompt="Select a folder: ")

# Check if a folder was selected
if [ -n "$selected_folder" ]; then
	# Run the mux command with the selected folder
	tmuxinator start vcluster folder="$selected_folder"
else
	echo "No folder selected."
fi
