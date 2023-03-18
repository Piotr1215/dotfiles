#!/usr/bin/env bash

# The set -e option instructs bash to immediately exit if any command has a non-zero exit status
# The set -u referencing a previously undefined  variable - with the exceptions of $* and $@ - is an error
# The set -o pipefaile if any command in a pipeline fails, that return code will be used as the return code of the whole pipeline
# https://bit.ly/37nFgin
set -eo pipefail

# Set new line and tab for word splitting
IFS=$'\n\t'

if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
	echo "Usage: $0 <script_or_function> [args...]"
	echo "Runs the given script or function with the bash '-x' option to show debug information."
	exit 0
fi

if [ -z "$1" ]; then
	echo "Usage: $0 <script_or_function> [args...]"
	exit 1
fi

function_exists() {
	declare -F "$1" >/dev/null
}

script_exists() {
	[ -f "$(which "$1")" ] && [ -x "$(which "$1")" ]
}

input_to_run="$1"
shift

header="Running: ${input_to_run}\nVersion: $(bash --version | head -n1)\nHostname: $(hostname)\nUsername: $(whoami)\n\n"

echo -e "${header}"

export PS4='+(${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): } \t '

if script_exists "$input_to_run"; then
	BASH_XTRACEFD=2 bash -x "$input_to_run" "$@"
elif function_exists "$input_to_run"; then
	temp_script=$(mktemp)

	echo "source ~/.zsh_functions" >>"$temp_script"
	echo "${input_to_run} \"\$@\"" >>"$temp_script"

	BASH_XTRACEFD=2 bash -x "$temp_script" "$@"

	rm "$temp_script"
else
	echo "Error: '$input_to_run' not found as a script or function. Please provide a valid script file or function name."
	exit 1
fi
