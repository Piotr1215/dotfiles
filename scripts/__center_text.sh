#!/bin/bash

# Function to center text horizontally
center_text() {
	# Get the terminal width
	term_width=$(tput cols)

	# Read all input lines
	figlet_output=$(cat)

	# Get the width of the longest line in the figlet output
	figlet_width=$(echo "$figlet_output" | awk '{print length}' | sort -nr | head -n1)

	# Calculate the left padding
	padding=$(((term_width - figlet_width) / 2))

	# Print the centered figlet output
	echo "$figlet_output" | while IFS= read -r line; do
		printf "%*s%s\n" "$padding" "" "$line"
	done
}

# Call the function to center text
center_text
