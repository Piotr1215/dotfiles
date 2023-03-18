#!/usr/bin/env bash

if [ -z "$1" ]; then
	echo "Usage: $0 <script_or_function> [args...]"
	exit 1
fi

input_to_run="$1"
shift

header="Running: ${input_to_run}\nVersion: $(bash --version | head -n1)\nHostname: $(hostname)\nUsername: $(whoami)\n\n"

echo -e "${header}"

export PS4='+(${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): } \t '

if [ -f "$input_to_run" ]; then
	BASH_XTRACEFD=2 bash -x "$input_to_run" "$@"
else
	temp_script=$(mktemp)

	echo "source ~/.zsh_functions" >>"$temp_script"
	echo "${input_to_run} \"\$@\"" >>"$temp_script"

	BASH_XTRACEFD=2 bash -x "$temp_script" "$@"

	rm "$temp_script"
fi
