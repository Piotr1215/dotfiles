#!/usr/bin/env bash

set -eo pipefail

# Add source and line number wher running in debug mode: __run_with_xtrace.sh __compare_files_content.sh
# Set new line and tab for word splitting
IFS=$'\n\t'

# Function to check if both files are provided
if [ $# -ne 2 ]; then
	echo "Usage: $0 <file1> <file2>"
	exit 1
fi

file1=$1
file2=$2

# Check if both files exist
if [ ! -f "$file1" ] || [ ! -f "$file2" ]; then
	echo "Both files must exist."
	exit 1
fi

echo "Comparing '$file1' (left) against '$file2' (right)"

# Perform the side-by-side diff with color output and file labels
diff -y --suppress-common-lines -w --label="$file1" --label="$file2" <(sort "$file1" | sed '/^$/d') <(sort "$file2" | sed '/^$/d') | colordiff
