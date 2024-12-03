#!/usr/bin/env bash
# Hide cursor and disable echo immediately
tput civis
stty -echo
# Restore cursor and echo on exit
trap 'tput cnorm; stty echo; exit 0' EXIT INT TERM
# Check for required commands
for cmd in figlet boxes; do
	if ! command -v "$cmd" &>/dev/null; then
		echo "Error: $cmd is required but not installed. Please install it and try again." >&2
		exit 1
	fi
done
# Default values
FIGLET_FONT="standard"
TOP_TEXT=""
EMOJI="💔" # Default emoji
START_DATE="2024-11-02 03:00:00"

# Function to get the dimensions of the terminal
get_terminal_dimensions() {
	stty size | awk '{print $2, $1}'
}

# Function to format time to DD HH:MM
format_time() {
	local total_seconds="$1"
	local days=$((total_seconds / 86400))
	local hours=$(((total_seconds % 86400) / 3600))
	local minutes=$(((total_seconds % 3600) / 60))
	printf "%d Days\n%02d Hours\n%02d Minutes" "$days" "$hours" "$minutes"
}

# Function to center text
center_text() {
	local text="$1"
	local width="$2"
	local text_length=${#text}
	local padding=$(((width - text_length) / 2))
	printf "%*s%s\n" $padding '' "$text"
}

# Add emoji display function
display_emoji() {
	local emoji="$1"
	local width="$2"
	# Center the emoji
	center_text "$emoji" "$width"
}

# Function to generate time display
generate_time_display() {
	local time="$1"
	local width="$2"
	# Generate figlet output for time
	local time_figlet=$(figlet -f $FIGLET_FONT "$time")
	# Box the time figlet
	local boxed_time=$(echo "$time_figlet" | boxes -d stone -p a2v1)
	# Center the boxed time
	echo "$boxed_time" | while IFS= read -r line; do
		center_text "$line" "$width"
	done
}

# Function to generate top text display
generate_top_text() {
	local text="$1"
	local width="$2"
	# Generate figlet output for top text
	local text_figlet=$(figlet -f $FIGLET_FONT -w $width "$text")
	# Center the top text
	echo "$text_figlet" | while IFS= read -r line; do
		center_text "$line" "$width"
	done
}

# Main count up function
countup() {
	local width height
	read -r width height <<<"$(get_terminal_dimensions)"
	# Clear the screen once at the beginning
	clear
	while true; do
		# Calculate elapsed time
		local now=$(date +%s)
		local start=$(date -d "$START_DATE" +%s)
		local elapsed=$((now - start))
		formatted_time=$(format_time "$elapsed")

		# Generate displays
		local top_display=""
		if [[ -n "$TOP_TEXT" ]]; then
			top_display=$(generate_top_text "$TOP_TEXT" "$width")
		fi
		time_display=$(generate_time_display "$formatted_time" "$width")

		# Calculate vertical centering
		local total_lines=$(($(echo "$top_display" | wc -l) + $(echo "$time_display" | wc -l) + 1)) # +1 for emoji
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

		# Display emoji below the box
		start_row=$((start_row + $(echo "$time_display" | wc -l) + 1))
		tput cup $start_row 0
		display_emoji "$EMOJI" "$width"

		sleep 60
	done
}

# Parse command line arguments
while getopts ":f:t:m:" opt; do
	case $opt in
	f)
		FIGLET_FONT="$OPTARG"
		;;
	t)
		TOP_TEXT="$OPTARG"
		;;
	m)
		EMOJI="$OPTARG"
		;;
	\?)
		echo "Invalid option -$OPTARG" >&2
		exit 1
		;;
	esac
done
shift $((OPTIND - 1))

# Run the count up timer
countup

# Clear the screen after exit
clear
