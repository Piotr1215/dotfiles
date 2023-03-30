#!/usr/bin/env bash

# Source generic error handling function
source __trap.sh

# The set -e option instructs bash to immediately exit if any command has a non-zero exit status
# The set -u referencing a previously undefined variable - with the exceptions of $* and $@ - is an error
# The set -o pipefaile if any command in a pipeline fails, that return code will be used as the return code of the whole pipeline
# https://bit.ly/37nFgin
set -o pipefail

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

# Set new line and tab for word splitting
IFS=$'\n' files=($(fzf-tmux --preview "bat --color=always {$1}" --reverse --query="$1" --multi --select-1 --exit-0 || handle_fzf_error))

# Check if any files were selected, and exit if not
if [ ${#files[@]} -eq 0 ]; then
	exit 0
fi

for i in "${!files[@]}"; do
	files[i]=$(realpath "${files[i]}")
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
