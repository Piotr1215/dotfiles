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
	echo "Opens recent git files in editor with:"
	echo "  - Shows 30 most recent files"
	echo "  - Ctrl-F: View all files"
	echo "  - ESC: Return to files recently changed"
	echo "  - Multi-file selection with smart splits"
	echo ""
	echo "Requires: git, fzf-tmux, bat"
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

# Generate the file list and verify each file path
file_list=$(
	set +o pipefail
	git log --pretty=format: --name-only -n 30 | grep . | awk '!seen[$0]++' | head -n 30
)

existing_files=$(echo "$file_list" | while IFS= read -r file; do
	if [ -f "$file" ]; then
		echo "$repo_root/$file"
	fi
done)

# Sort and list files
# Function to get the full file list
get_full_file_list() {
	echo "$existing_files" | awk '!seen[$0]++'
}

# Use fzf-tmux to select from the sorted list
IFS=$'\n' files=($(get_full_file_list | fzf-tmux \
	--preview "bat --color=always {}" \
	--reverse \
	--multi \
	--select-1 \
	--exit-0 \
	--bind "ctrl-f:reload(git ls-tree -r HEAD --name-only || handle_fzf_error)" \
	--bind "esc:reload(echo \"$existing_files\" | awk '!seen[\$0]++' || handle_fzf_error)" \
	--bind "change:top" \
	--info=inline \
	--prompt "Select git files (Ctrl-f: all files, ESC: recent changes) > " ||
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
