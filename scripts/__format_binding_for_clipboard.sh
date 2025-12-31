#!/usr/bin/env bash
# Transform a binding line into formatted output with aligned headers
# Input: formatted line from fzf (space-separated columns)
# Output: header + data, perfectly aligned with pipes

set -eo pipefail

DOTFILES="${DOTFILES:-$HOME/dev/dotfiles}"
# Read from stdin or arg
if [[ -n "$1" ]]; then
    input="$1"
    # Strip leading/trailing single quotes if present
    input="${input#\'}"
    input="${input%\'}"
else
    read -r input
fi

# Extract the file:line from end of input to find matching raw line
file_line=$(echo "$input" | awk '{print $NF}')

# Find the raw pipe-delimited line from confhelp that matches
# Use fixed-string grep to avoid regex escaping issues with special chars like ^
raw_line=$(confhelp -b "$DOTFILES" | grep -F "|${file_line}" | head -1)

if [[ -z "$raw_line" ]]; then
    # Fallback: just output with simple header
    printf "SOURCE | KEY | COMMAND | FILE:LINE\n%s\n" "$input"
else
    # Format header + raw line together for perfect alignment
    printf "SOURCE|KEY|COMMAND|FILE:LINE\n%s\n" "$raw_line" | column -t -s'|' -o' | '
fi
