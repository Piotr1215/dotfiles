#!/usr/bin/env bash

# Hide cursor and disable echo immediately
tput civis
stty -echo

# Restore cursor and echo on exit
trap 'tput cnorm; stty echo; exit 0' EXIT INT TERM

# Check for required commands
for cmd in figlet boxes lolcat; do
	if ! command -v "$cmd" &>/dev/null; then
		echo "Error: $cmd is required but not installed. Please install it and try again." >&2
		exit 1
	fi
done

# Default values
FIGLET_FONT="slant"
TOP_TEXT=""

# Function to get the dimensions of the terminal
get_terminal_dimensions() {
	stty size | awk '{print $2, $1}'
}

# Function to format seconds to HH : MM : SS
format_time() {
	local total_seconds="$1"
	local hours=$((total_seconds / 3600))
	local minutes=$(((total_seconds % 3600) / 60))
	local seconds=$((total_seconds % 60))
	printf "%02d : %02d : %02d" "$hours" "$minutes" "$seconds"
}

# Function to center text
center_text() {
	local text="$1"
	local width="$2"
	local text_length=${#text}
	local padding=$(((width - text_length) / 2))
	printf "%*s%s\n" $padding '' "$text"
}

# Function to generate colored time display
generate_time_display() {
	local time="$1"
	local width="$2"

	# Generate figlet output for time
	local time_figlet=$(figlet -f $FIGLET_FONT "$time")

	# Box the time figlet
	local boxed_time=$(echo "$time_figlet" | boxes -d stone -p a2v1)

	# Center and colorize the boxed time
	echo "$boxed_time" | while IFS= read -r line; do
		center_text "$line" "$width"
	done | lolcat -f -s 150
}

# Function to generate top text display
generate_top_text() {
	local text="$1"
	local width="$2"

	# Generate figlet output for top text
	local text_figlet=$(figlet -f $FIGLET_FONT -w $width "$text")

	# Center and colorize the top text
	echo "$text_figlet" | while IFS= read -r line; do
		center_text "$line" "$width"
	done | lolcat -f -s 150
}

# Main countdown function
countdown() {
	local total_seconds="$1"
	local width height
	read -r width height <<<"$(get_terminal_dimensions)"

	# Clear the screen once at the beginning
	clear

	for ((i = total_seconds; i >= 0; i--)); do
		formatted_time=$(format_time "$i")

		# Generate top text display if provided
		local top_display=""
		if [[ -n "$TOP_TEXT" ]]; then
			top_display=$(generate_top_text "$TOP_TEXT" "$width")
		fi

		# Generate time display
		time_display=$(generate_time_display "$formatted_time" "$width")

		# Calculate vertical centering
		local total_lines=$(($(echo "$top_display" | wc -l) + $(echo "$time_display" | wc -l)))
		local start_row=$(((height - total_lines) / 2))

		# Clear screen and move cursor to start position
		tput cup 0 0
		tput ed

		# Display top text if provided
		if [[ -n "$top_display" ]]; then
			tput cup $start_row 0
			echo -e "$top_display"
			start_row=$((start_row + $(echo "$top_display" | wc -l) + 1))
		fi

		# Display centered time
		tput cup $start_row 0
		echo -e "$time_display"

		sleep 1
	done
}

# Parse command line arguments
while getopts ":f:t:" opt; do
	case $opt in
	f)
		FIGLET_FONT="$OPTARG"
		;;
	t)
		TOP_TEXT="$OPTARG"
		;;
	\?)
		echo "Invalid option -$OPTARG" >&2
		exit 1
		;;
	esac
done

shift $((OPTIND - 1))

# Check if a time argument is provided
if [ $# -eq 0 ]; then
	echo "Usage: $0 [-f font] [-t 'top text'] <seconds_to_countdown>"
	exit 1
fi

# Validate the input
if ! [[ $1 =~ ^[0-9]+$ ]]; then
	echo "Error: Please provide a positive integer for the number of seconds."
	exit 1
fi

# Run the countdown
countdown "$1"

# Clear the screen after countdown
clear
