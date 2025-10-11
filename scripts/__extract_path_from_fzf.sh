#!/usr/bin/env bash
# Extract path from fzf selection (handles bookmarks and regular paths)

set -eo pipefail

line="$1"

# Check if it's a bookmark entry (description followed by path)
# Bookmarks are formatted as: "description (padded to 60 chars) path"
# Match pattern: [space] [path starting with / or ~] [extending to end of line]
# This handles paths with spaces correctly
if [[ "$line" =~ [[:space:]]([/~][^[:space:]].*)$ ]]; then
    # Extract path from bookmark format (everything after the last space before path)
    path="${BASH_REMATCH[1]}"
elif [[ "$line" =~ ^[/~] ]]; then
    # Line starts with path
    path="$line"
else
    # Try to extract last field as path
    last_field=$(echo "$line" | awk '{print $NF}')
    if [[ "$last_field" =~ ^[/~] ]]; then
        path="$last_field"
    else
        # Fall back to entire line
        path="$line"
    fi
fi

# Expand tilde and resolve to absolute path
expanded_path="${path/#\~/$HOME}"
# Use printf to avoid trailing newline
printf '%s' "$(realpath "$expanded_path" 2>/dev/null || echo "$expanded_path")"
