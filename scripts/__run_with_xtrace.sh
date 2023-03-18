#!/usr/bin/env bash

# Check if a script or function name is provided
if [ -z "$1" ]; then
	echo "Usage: $0 <script_or_function> [args...]"
	exit 1
fi

input_to_run="$1"
shift

# Header with static information
header="Running: ${input_to_run}\nVersion: $(bash --version | head -n1)\nHostname: $(hostname)\nUsername: $(whoami)\n\n"

# Display the header
echo -e "${header}"

# Set PS4 to show only the changing information
export PS4='+(${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): } \t '

# Check if the input is a script file or a function
if [ -f "$input_to_run" ]; then
	# Run the provided script with the -x option and any additional arguments
	BASH_XTRACEFD=3 bash 3> >(cat) -x "$input_to_run" "$@"
else
	# Create a temporary script file
	temp_script=$(mktemp)

	# Source the functions file and run the function in the temporary script
	echo "source ~/.zsh_functions" >>"$temp_script"
	echo "${input_to_run} \"\$@\"" >>"$temp_script"

	# Run the temporary script with the -x option and any additional arguments
	BASH_XTRACEFD=3 bash -x "$temp_script" "$@"

	# Remove the temporary script file
	rm "$temp_script"
fi
