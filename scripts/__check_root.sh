#!/usr/bin/env bash

# The set -e option instructs bash to immediately exit if any command has a non-zero exit status
# The set -u referencing a previously undefined  variable - with the exceptions of $* and $@ - is an error
# The set -o pipefaile if any command in a pipeline fails, that return code will be used as the return code of the whole pipeline
# https://bit.ly/37nFgin
set -euo pipefail

# Add source and line number wher running in debug mode: bash -xv __check_root.sh
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

# Set new line and tab for word splitting
IFS=$'\n\t'

help_function() {
	echo "Usage: __check_root.sh [-h|--help]"
	echo ""
	echo "This script checks if the user is running as root or has the correct sudo password."
	echo "It sets specific bash options for error handling and provides debug options."
	echo ""
	echo "Options:"
	echo "  -h, --help    Show this help message and exit."
	echo ""
	echo "Features:"
	echo "  - Sets specific bash options for error handling (set -euo pipefail)."
	echo "  - Checks if the user is already root or has the correct sudo password."
	echo "  - Exits with an error message if the sudo password is incorrect."
	echo ""
	echo "Note: Debug options can be enabled with 'bash -xv __check_root.sh'."
}

if [[ -n "${1-}" && ("$1" == "-h" || "$1" == "--help") ]]; then
	help_function
	exit 0
fi

if [[ "$EUID" = 0 ]]; then
	echo "(1) already root"
else
	sudo -k # make sure to ask for password on next sudo
	if sudo true; then
		echo "(2) correct password"
	else
		echo "(3) wrong password"
		exit 1
	fi
fi
