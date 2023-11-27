#!/bin/bash

# Get the ID of the first visible Alacritty window
window=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)
if [ -n "$window" ]; then
	# Unmaximize the window
	xdotool windowunmap "$window"

	# Resize the window
	xdotool windowmap "$window"
	# Resize and move the window to the left side of the screen with exact pixel dimensions
	xdotool windowsize "$window" 1920 2128
	xdotool windowmove "$window" 0 32
	xdotool windowactivate --sync "$window"

else
	echo "No Alacritty window found."
fi

# Get the ID of the first Firefox window across all workspaces
firefox_window=$(xdotool search --classname Navigator | head -n 1)
if [ -n "$firefox_window" ]; then
	# Unmaximize the window

	# Resize and move the Firefox window to the right side of the screen with exact pixel dimensions
	wmctrl -i -r "$firefox_window" -b remove,maximized_vert,maximized_horz
	# Assuming the screen resolution width is 3840, half of it is 1920
	# Adjust the height according to your screen resolution
	xdotool windowsize "$firefox_window" 1946 2154
	# Move the Firefox window to the right side of the screen
	# The x-coordinate is set to 1920 to position the window on the right half of the screen
	xdotool windowmove "$firefox_window" 1907 21
	sleep 0.2
	xdotool windowactivate --sync "$firefox_window" key ctrl+super+Right
else
	echo "No Firefox window found."
fi
