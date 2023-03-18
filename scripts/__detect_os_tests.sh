#!/usr/bin/env bash

# The set -e option instructs bash to immediately exit if any command has a non-zero exit status
# The set -u referencing a previously undefined  variable - with the exceptions of $* and $@ - is an error
# The set -o pipefaile if any command in a pipeline fails, that return code will be used as the return code of the whole pipeline
# https://bit.ly/37nFgin
set -eo pipefail

# Add source and line number wher running in debug mode: bash -xv testme.sh
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

# Set new line and tab for word splitting
IFS=$'\n\t'

source ./__detect_os.sh

# Mock uname function
uname() {
	if [[ $1 == "-m" ]]; then
		echo "$mock_arch"
	else
		command uname "$@"
	fi
}

# Test function
run_test() {
	local expected_output=$1
	local actual_output=$(detect_os)

	echo "Expected: $expected_output"
	echo "Actual: $actual_output"

	if [[ "$expected_output" != "$actual_output" ]]; then
		echo "Test failed"
		exit 1
	else
		echo "Test passed"
	fi
}

# Test cases
echo "Test case 1: M1"
OSTYPE="darwin"
mock_arch="arm64"
run_test "M1"

echo "Test case 2: Mac (Intel)"
OSTYPE="darwin"
mock_arch="x86_64"
run_test "mac"

echo "Test case 3: Linux (x86_64)"
OSTYPE="linux-gnu"
mock_arch="x86_64"
run_test "linux"

echo "Test case 4: Linux (ARM)"
OSTYPE="linux-gnu"
mock_arch="arm"
run_test "linux"

echo "Test case 5: Linux (ARM64)"
OSTYPE="linux-gnu"
mock_arch="arm64"
run_test "linux"

echo "Test case 6: Unsupported OS"
OSTYPE="unsupported_os"
mock_arch="x86_64"
run_test "Unsupported OS"
