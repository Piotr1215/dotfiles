#!/usr/bin/env bash

# The set -e option instructs bash to immediately exit if any command has a non-zero exit status
# The set -u referencing a previously undefined  variable - with the exceptions of $* and $@ - is an error
# The set -o pipefaile if any command in a pipeline fails, that return code will be used as the return code of the whole pipeline
# https://bit.ly/37nFgin

set -eo pipefail
# Add source and line number wher running in debug mode: bash -xv __tmux_record.sh
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

# Set new line and tab for word splitting
IFS=$'\n\t'

recording="$PWD"/tmux-"$session"-"$RANDOM".cast
echo "Recording will start to $recording"
echo "Exit tmux <c-d> or F12 to stop and save the recording"
echo ""

if [[ -z $TMUX ]]; then

	if ! tmux list-sessions >/dev/null 2>&1; then
		echo "There are no active tmux sessions, create one first."
		exit 1
	fi

	session=$(tmux list-sessions | awk '{print $1}' | tr -d ":" | fzf)

	tmux detach -s "$session"
	asciinema rec --command "tmux attach -t $session" "$recording"

else
	echo 'The $TMUX variable is set, start a new terminal without tmux'
fi
