#!/usr/bin/env bash

# Simple git history for a file - latest changes only
# Usage: ./git_history.sh <file_path> [number_of_commits]

FILE_PATH="$1"
LIMIT="${2:-5}"  # Default to 5 commits

if [ -z "$FILE_PATH" ]; then
    echo "Usage: $0 <file_path> [number_of_commits]"
    echo "Example: $0 .github/workflows/backport.yaml 3"
    exit 1
fi

if [ ! -f "$FILE_PATH" ]; then
    echo "Error: File '$FILE_PATH' does not exist"
    exit 1
fi

echo "=== Latest $LIMIT changes to: $FILE_PATH ==="
echo

# Show recent commits that touched this file
git log -n "$LIMIT" --oneline --follow -- "$FILE_PATH"

echo
echo "=== Latest change details ==="
echo

# Show the diff for the most recent change
git log -n 1 --patch --follow -- "$FILE_PATH"
