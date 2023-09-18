#!/bin/bash

# Extracting the line number and file path from the input string
LINE_NUMBER=$(echo "$1" | awk -F ':' '{print $2}')
FILE_PATH=$(echo "$1" | awk -F ':' '{print $3}')

# Use all arguments beyond the first one as the TASK_DESCRIPTION
shift
TASK_DESCRIPTION="$@"

# If a task description is provided, search for the line number containing that description
if [ ! -z "$TASK_DESCRIPTION" ]; then
	NEW_LINE_NUMBER=$(grep -n -F "$TASK_DESCRIPTION" "$FILE_PATH" | awk -F ':' '{print $1}' | head -n 1)
	if [ ! -z "$NEW_LINE_NUMBER" ]; then
		LINE_NUMBER=$NEW_LINE_NUMBER
	fi
fi

# Opening the file with neovim at the specific line number and highlighting it
nvim +$LINE_NUMBER "$FILE_PATH"
