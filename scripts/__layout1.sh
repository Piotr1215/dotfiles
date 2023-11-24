#!/bin/bash

# layout1.sh
# Check if Alacritty is running
if pgrep -x "alacritty" >/dev/null; then
	# Get the ID of the first visible Alacritty window
	window=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)
	if [ -n "$window" ]; then
		# Unmaximize the window
		xdotool windowunmap "$window"

		# Resize the window
		xdotool windowmap "$window"
		# Resize and move the window to the left side of the screen with exact pixel dimensions

		wmctrl -i -r "$window" -b add,maximized_vert,maximized_horz

		# wmctrl -r Alacritty -e 0,1920,0,-1,-1

		xdotool windowactivate --sync "$window"
		xdotool windowraise "$window"
	else
		echo "No Alacritty window found."
	fi

else
	# Launch Alacritty
	echo "Please launch Alacritty first."
fi
