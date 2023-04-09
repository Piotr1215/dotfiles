#!/usr/bin/env bash

# This script launches a URL in the default browser
# without setting focus to the browser
# Source generic error handling funcion
source __trap.sh

# The set -e option instructs bash to immediately exit if any command has a non-zero exit status
# The set -u referencing a previously undefined  variable - with the exceptions of $* and $@ - is an error
# The set -o pipefaile if any command in a pipeline fails, that return code will be used as the return code of the whole pipeline
# https://bit.ly/37nFgin
set -eo pipefail

# Add source and line number wher running in debug mode: __run_with_xtrace.sh __launch_url.sh
# Set new line and tab for word splitting
IFS=$'\n\t'

# Check if any arguments are provided
if [ $# -eq 0 ]; then
	echo "Please provide at least one URL as an argument. 😿"
	exit 1
fi

# Function to check if URL is accessible
is_accessible_url() {
	if curl -Is "$1" >/dev/null 2>&1; then
		return 0
	else
		return 1
	fi
}

# Function to build a valid URL
build_valid_url() {
	local input_url="$1"
	local url

	if [[ ! "$input_url" =~ ^https?:// ]]; then
		url="https://$input_url"
	else
		url="$input_url"
	fi

	if is_accessible_url "$url"; then
		echo "$url"
	else
		for ext in ".com" ".net" ".org"; do
			modified_url="${url%%.*}${ext}"
			if is_accessible_url "$modified_url"; then
				echo "$modified_url"
				break
			fi
		done
	fi
}

# Save the active window ID
active_window_id=$(xdotool getactivewindow)

# Loop through provided arguments and open valid URLs
for input_url in "$@"; do
	valid_url=$(build_valid_url "$input_url")

	if [ -n "$valid_url" ]; then
		# Open the URL
		xdg-open "$valid_url" >/dev/null 2>&1 &

		# Wait for the browser to open the URL
		sleep 1
	else
		echo "Couldn't find a valid URL for: $input_url 🤖"
	fi
done

# Return focus to the terminal
xdotool windowactivate "$active_window_id"
