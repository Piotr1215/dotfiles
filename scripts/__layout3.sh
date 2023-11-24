#!/bin/bash

# layout2.sh
# Get the IDs of the first two Firefox windows across all workspaces
firefox_windows=($(xdotool search --classname Navigator | head -n 2))
if [ ${#firefox_windows[@]} -eq 2 ]; then
	# Iterate over the two windows and position them
	for i in 0 1; do
		window_id=${firefox_windows[$i]}
		wmctrl -i -r "$window_id" -b remove,maximized_vert,maximized_horz

		# Resize the window
		xdotool windowmap "$window_id"
		xdotool windowsize "$window_id" 1946 2154

		# Move the window to the left or right side of the screen
		if [ $i -eq 0 ]; then
			# Move the first window to the left side of the screen
			xdotool windowmove "$window_id" -13 21
		else
			# Move the second window to the right side of the screen
			xdotool windowmove "$window_id" 1910 0
		fi
	done
else
	echo "Not enough Firefox windows found."
fi
