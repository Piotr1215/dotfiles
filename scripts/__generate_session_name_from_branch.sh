#!/usr/bin/env bash

# Check if the folder path was passed as an argument
if [ -z "$1" ]; then
	echo "Error: No folder path provided"
	exit 1
fi

# Set the folder name from the argument
folder_name=$(basename "$1")

# Change to the provided folder path
cd "$1" || exit 1

# Try to get the Git branch name, fallback to 'no-branch' if not a Git repo
branch_name=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "no-branch")

# Output the session name
echo "$folder_name-$branch_name"
