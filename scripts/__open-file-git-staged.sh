#!/usr/bin/env bash

# Source generic error handling function
source __trap.sh

# The set -e option instructs bash to immediately exit if any command has a non-zero exit status
# The set -u referencing a previously undefined variable - with the exceptions of $* and $@ - is an error
# The set -o pipefaile if any command in a pipeline fails, that return code will be used as the return code of the whole pipeline
# https://bit.ly/37nFgin
set -o pipefail

help_function() {
	echo "Usage: __open-file-git.sh [-h|--help]"
	echo ""
	echo "This script opens files from the Git repository using fzf-tmux for selection and the configured editor (default: nvim) for viewing."
	echo "It lists the files from the Git log, allows multi-selection, and opens them in different layouts depending on the number of files selected."
	echo ""
	echo "Options:"
	echo "  -h, --help    Show this help message and exit."
	echo ""
	echo "Features:"
	echo "  - Sources a generic error handling function from __trap.sh."
	echo "  - Gets the repository root path using 'git rev-parse --show-toplevel'."
	echo "  - Lists files from the Git log and filters them using fzf-tmux."
	echo "  - Opens selected files in the configured editor (default: nvim) with different layouts."
	echo "  - Handles interruptions and errors gracefully."
	echo ""
	echo "Note: This script requires Git, fzf-tmux, and a compatible editor (e.g., nvim)."
}

# Check for help argument
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
	help_function
	exit 0
fi

# Custom error handling function for fzf-tmux
handle_fzf_error() {
	if [ $? -eq 130 ]; then
		# If fzf-tmux was interrupted by Ctrl+C (exit code 130), exit gracefully
		exit 0
	else
		# Otherwise, re-raise the error
		return $?
	fi
}

# Add source and line number when running in debug mode: __run_with_xtrace.sh __open-file.sh

# Get the repository root path
repo_root=$(git rev-parse --show-toplevel)

IFS=$'\n' files=($(git status -s | awk '{print $2}' | grep -v '^$' | fzf-tmux --preview "bat --color=always {}" --reverse --multi --select-1 --exit-0 || handle_fzf_error))

# Check if any files were selected, and exit if not test
if [ ${#files[@]} -eq 0 ]; then
	exit 0
fi

for i in "${!files[@]}"; do
	files[i]=$(realpath "$repo_root/${files[i]}")
done

case "${#files[@]}" in
2)
	${EDITOR:-nvim} -O "${files[@]}"
	;;
3)
	${EDITOR:-nvim} -O "${files[0]}" -c 'wincmd j' -c "vsplit ${files[1]}" -c "split ${files[2]}"
	;;
4)
	${EDITOR:-nvim} -O "${files[0]}" -c "vsplit ${files[1]}" -c "split ${files[2]}" -c 'wincmd h' -c "split ${files[3]}"
	;;
*)
	${EDITOR:-nvim} "${files[@]}"
	;;
esac
