#!/bin/bash

# Function to select a file using fzf
select_file() {
	find .. -type f -name "*.mdx" | fzf --height 40% --reverse --prompt="Select $1 file: "
}

# Select the first file
FILE1=$(select_file "first")

# If no file was selected, exit
if [ -z "$FILE1" ]; then
	echo "No file selected. Exiting."
	exit 1
fi

# Select the second file
FILE2=$(select_file "second")

# If no file was selected, exit
if [ -z "$FILE2" ]; then
	echo "No file selected. Exiting."
	exit 1
fi

# Debug: Print selected files
echo "Selected files:"
echo "File 1: $FILE1"
echo "File 2: $FILE2"

# Function to perform diff
perform_diff() {
	local file1="$1"
	local file2="$2"
	echo "Performing diff between:"
	echo "$file1"
	echo "$file2"
	if [ -f "$file1" ] && [ -f "$file2" ]; then
		diff --unified=0 "$file1" "$file2" | diff-so-fancy
	else
		echo "Error: One or both files do not exist."
		[ ! -f "$file1" ] && echo "File does not exist: $file1"
		[ ! -f "$file2" ] && echo "File does not exist: $file2"
	fi
}

# Use entr to watch for changes and perform diff
(
	echo "$FILE1"
	echo "$FILE2"
) | entr -s "$(declare -f perform_diff); perform_diff '$FILE1' '$FILE2'"

# Optionally, you can add a prompt to press any key to exit
read -n 1 -s -r -p "Press any key to exit..."
