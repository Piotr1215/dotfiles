#!/usr/bin/env bash

# Source generic error handling function
source __trap.sh

# The set -e option instructs bash to immediately exit if any command has a non-zero exit status
# The set -u referencing a previously undefined variable - with the exceptions of $* and $@ - is an error
# The set -o pipefail if any command in a pipeline fails, that return code will be used as the return code of the whole pipeline
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
	echo "  - New: Press Ctrl+F in the fzf menu to show only files changed in the current branch."
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

# Get the repository root path and change to the repo root directory
repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root" || {
	echo "Failed to change to repository root directory"
	exit 1
}

# Determine the base branch
if git show-ref --quiet refs/heads/main; then
	base_branch=main
elif git show-ref --quiet refs/heads/master; then
	base_branch=master
else
	# Default to 'main' if neither 'main' nor 'master' exists
	base_branch=main
fi

# Get the merge base between HEAD and the base branch
merge_base=$(git merge-base HEAD "$base_branch")

# Generate the file list and verify each file path
file_list=$(git ls-tree -r HEAD --name-only)
existing_files=$(echo "$file_list" | while IFS= read -r file; do
	if [ -f "$file" ]; then
		echo "$repo_root/$file"
	fi
done)

# Sort and list files
sorted_files=$(echo "$existing_files" | xargs -d '\n' ls -lt 2>/dev/null)

# Function to get the full file list
get_full_file_list() {
	echo "$sorted_files" | awk '{print $9}' | awk '!seen[$0]++' | grep -v '^$'
}

# Function to get the files changed in the current branch
get_changed_files() {
	git diff --name-only "$merge_base"..HEAD
}

# Use fzf-tmux to select from the sorted list
IFS=$'\n' files=($(get_full_file_list | fzf-tmux \
	--preview "bat --color=always {}" \
	--reverse \
	--multi \
	--select-1 \
	--exit-0 \
	--bind "ctrl-f:reload(git diff --name-only $merge_base..HEAD || handle_fzf_error)" \
	--bind "change:top" \
	--info=inline \
	--prompt "Select git files (Ctrl-f: only changed in branch) > " ||
	handle_fzf_error))

# Check if any files were selected, and exit if not
if [ ${#files[@]} -eq 0 ]; then
	echo "No files were selected. Exiting."
	exit 0
fi

# Directly use the full paths in the case statement
case "${#files[@]}" in
2)
	${EDITOR:-nvim} -O +'normal g;' "${files[@]}"
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
