#!/usr/bin/env bash

# Define a function to print the error message and exit with a non-zero status
print_error() {
	echo "ERROR: An error occurred in the script \"$0\" on line $1" >>error-pipe
	cat error-pipe >&2
	exit 1
}

# Set the error trap
trap 'print_error $? $LINENO' ERR
