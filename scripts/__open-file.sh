#!/usr/bin/env bash

# The set -e option instructs bash to immediately exit if any command has a non-zero exit status
# The set -o pipefaile if any command in a pipeline fails, that return code will be used as the return code of the whole pipeline
# https://bit.ly/37nFgin
set -eo pipefail

# Add source and line number wher running in debug mode: bash -xv __open-file.sh
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

# Set new line and tab for word splitting
IFS=$'\n' files=($(fzf-tmux --preview "bat --color=always {$1}" --reverse --query="$1" --multi --select-1 --exit-0))
if [[ "${#files[@]}" -gt 2 ]]; then

	[[ -n "$files" ]] && ${EDITOR:-nvim} -p "${files[@]}"
else
	[[ -n "$files" ]] && ${EDITOR:-nvim} -O "${files[@]}"
fi
