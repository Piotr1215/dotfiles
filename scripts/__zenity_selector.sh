#!/bin/bash

# Assigns command line arguments to variables
message="Add a pet link, create a taskwarrior task, add song to MPV playlist, create web Highlight"

selected_option=$(zenity --list --title="Choose an Action" \
	--text="$message" \
	--column="Actions" "Link" "Task" "Playlist" "Highlights" \
	--multiple \
	--separator=" " \
	--height=220)

# Outputs the exit status and selected options separated by a newline
echo "$selected_option"

exit 0
