#!/bin/bash

# layout1.sh
# Get the ID of the first visible Alacritty window
window=$(xdotool search --onlyvisible --classname Navigator | head -n 1)
if [ -n "$window" ]; then

	wmctrl -i -r "$window" -b remove,maximized_vert,maximized_horz
	# Resize the window
	xdotool windowmap "$window"
	# Resize and move the window to the left side of the screen with exact pixel dimensions
	wmctrl -i -r "$window" -b add,maximized_vert,maximized_horz

	xdotool windowactivate --sync "$window"
	xdotool windowraise "$window"
else
	echo "No Firefox window found."
fi
