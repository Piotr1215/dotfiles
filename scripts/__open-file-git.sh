#!/usr/bin/env bash
source __trap.sh
set -o pipefail

help_function() {
	echo "Usage: __open-file-git.sh [-h|--help]"
	echo ""
	echo "This script opens files from the Git repository using fzf-tmux for selection and the configured editor (default: nvim) for viewing."
	echo "It lists files changed in the current branch by default, with Ctrl+F to show all repository files."
	echo ""
	echo "Options:"
	echo "  -h, --help    Show this help message and exit."
	echo ""
	echo "Features:"
	echo "  - Sources a generic error handling function from __trap.sh."
	echo "  - Gets the repository root path using 'git rev-parse --show-toplevel'."
	echo "  - Lists files changed in current branch by default."
	echo "  - Opens selected files in the configured editor (default: nvim) with different layouts."
	echo "  - Handles interruptions and errors gracefully."
	echo "  - Press Ctrl+F to show all files in the repository."
	echo ""
	echo "Note: This script requires Git, fzf-tmux, and a compatible editor (e.g., nvim)."
}

if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
	help_function
	exit 0
fi

handle_fzf_error() {
	if [ $? -eq 130 ]; then
		exit 0
	else
		return $?
	fi
}

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root" || {
	echo "Failed to change to repository root directory"
	exit 1
}

if git show-ref --quiet refs/heads/main; then
	base_branch=main
elif git show-ref --quiet refs/heads/master; then
	base_branch=master
else
	base_branch=main
fi

merge_base=$(git merge-base HEAD "$base_branch")

# Check if there are any changed files
changed_files=$(git diff --name-only "$merge_base"..HEAD)
if [ -z "$changed_files" ]; then
	initial_cmd="git ls-tree -r HEAD --name-only | sort -r"
	prompt_text="Select git files (Ctrl-f: all files) > "
	reload_cmd="git ls-tree -r HEAD --name-only | sort -r"
else
	initial_cmd="git diff --name-only $merge_base..HEAD"
	prompt_text="Select changed files (Ctrl-f: all files) > "
	reload_cmd="git ls-tree -r HEAD --name-only | sort -r"
fi

IFS=$'\n' files=($(eval "$initial_cmd" | fzf-tmux \
	--preview "bat --color=always {}" \
	--reverse \
	--multi \
	--select-1 \
	--exit-0 \
	--bind "ctrl-f:reload($reload_cmd || handle_fzf_error)" \
	--bind "change:top" \
	--info=inline \
	--prompt "$prompt_text" ||
	handle_fzf_error))

if [ ${#files[@]} -eq 0 ]; then
	echo "No files were selected. Exiting."
	exit 0
fi

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
