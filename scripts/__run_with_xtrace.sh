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

input_to_run="$1"
shift

header="Running: ${input_to_run}\nVersion: $(bash --version | head -n1)\nHostname: $(hostname)\nUsername: $(whoami)\n\n"

echo -e "${header}"

export PS4='+(${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): } \t '

BASH_XTRACEFD=2 bash -x "$input_to_run" "$@"
