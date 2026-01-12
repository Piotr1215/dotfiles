#!/usr/bin/env bash

# The set -e option instructs bash to immediately exit if any command has a non-zero exit status
# The set -u referencing a previously undefined  variable - with the exceptions of $* and $@ - is an error
# The set -o pipefaile if any command in a pipeline fails, that return code will be used as the return code of the whole pipeline
# https://bit.ly/37nFgin
set -eo pipefail

# Set new line and tab for word splitting
IFS=$'\n\t'
help_function() {
	echo "Usage: __run_with_trace.sh <script_or_function> [args...] [-h|--help]"
	echo ""
	echo "This script runs the given script or function with the bash '-x' option to show debug information."
	echo "It prints the version of bash, hostname, and username before executing the script or function."
	echo ""
	echo "Options:"
	echo "  -h, --help    Show this help message and exit."
	echo ""
	echo "Arguments:"
	echo "  <script_or_function>    The script or function to run with debug information. Required."
	echo "  [args...]               Optional arguments to pass to the script or function."
	echo ""
	echo "Features:"
	echo "  - Executes the script or function with the bash '-x' option for tracing."
	echo "  - Prints additional information such as bash version, hostname, and username."
	echo "  - Provides clear usage instructions."
	echo ""
	echo "Example:"
	echo "  __run_with_trace.sh ./myscript.sh arg1 arg2"
	echo ""
	echo "Note: Ensure that the script or function to be run has execute permissions."
}

if [ -z "$1" ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
	help_function
	exit 0
fi

input_to_run="$1"
shift

header="Running: ${input_to_run}\nVersion: $(bash --version | head -n1)\nHostname: $(hostname)\nUsername: $(whoami)\n\n"

echo -e "${header}"

export PS4='+(${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): } \t '

# Add DEBUG trap for stepping through (optional: set STEP=1 to pause each line)
if [[ "${STEP:-}" == "1" ]]; then
	{
		echo 'shopt -s extdebug; set -T'
		echo 'trap '\''echo -e "\033[36m[before]\033[0m $BASH_COMMAND"; read -n1 -s </dev/tty; echo'\'' DEBUG'
		cat "$input_to_run"
	} | bash -s -- "$@"
else
	BASH_XTRACEFD=2 bash -x "$input_to_run" "$@"
fi
