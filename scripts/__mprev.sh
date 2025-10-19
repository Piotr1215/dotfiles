#!/usr/bin/env bash

# The set -e option instructs bash to immediately exit if any command has a non-zero exit status
# The set -u referencing a previously undefined variable - with the exceptions of $* and $@ - is an error
# The set -o pipefaile if any command in a pipeline fails, that return code will be used as the return code of the whole pipeline
# https://bit.ly/37nFgin
set -eo pipefail

help_function() {
	echo "Usage: __mprev.sh [file] [-h|--help]"
	echo ""
	echo "This script opens a markdown file in neovim and activates the markdown preview."
	echo "If no file is provided, it defaults to README.md in the current directory."
	echo ""
	echo "Options:"
	echo "  -h, --help    Show this help message and exit."
	echo ""
	echo "Arguments:"
	echo "  [file]        Optional markdown file to preview. Defaults to README.md"
	echo ""
	echo "Features:"
	echo "  - Opens the specified markdown file in neovim"
	echo "  - Automatically triggers MarkdownPreview"
	echo "  - Sets up Firefox/Alacritty side-by-side layout"
	echo ""
	echo "Note: This script requires markdown-preview.nvim plugin and Firefox browser."
}

# Check for help argument
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
	help_function
	exit 0
fi

# Default to README.md if no argument provided
file="${1:-README.md}"

# Check if file exists
if [[ ! -f "$file" ]]; then
	echo "Error: File '$file' not found" >&2
	exit 1
fi

# Check if file is a markdown file
if [[ ! "$file" =~ \.(md|markdown)$ ]]; then
	echo "Warning: '$file' does not appear to be a markdown file" >&2
fi

# Get the directory where this script is located
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Open nvim with the file and trigger MarkdownPreview in background
# Run layout setup after a delay to allow preview to open, but only if nvim is still running
(
	sleep 1.5
	# Only trigger layout if parent script is still running (nvim is active)
	if ps -p $$ > /dev/null 2>&1; then
		"$script_dir/__layouts.sh" 2 2>/dev/null
	fi
) &
layout_pid=$!

# Open nvim (this blocks until user exits)
${EDITOR:-nvim} "$file" -c "MarkdownPreview"

# Kill the background layout job if it's still waiting
kill $layout_pid 2>/dev/null || true

# On exit, maximize Alacritty
"$script_dir/__layouts.sh" 1 2>/dev/null || true
