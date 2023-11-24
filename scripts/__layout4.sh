#!/bin/bash

slack=$(xdotool search --onlyvisible --classname Slack | head -n 1)
if [[ -z "${slack}" ]]; then
	echo "No Slack window found"
	/home/decoder/dev/dotfiles/scripts/__layout2.sh
	exit 0
fi

# Get the ID of the first Firefox window across all workspaces
slack_window=$(xdotool search --onlyvisible --classname Slack | head -n 1)
if [ -n "$slack_window" ]; then

	wmctrl -i -r "$slack_window" -b remove,maximized_vert,maximized_horz

	xdotool windowmap "$slack_window"
	# Resize and move the window to the left side of the screen with exact pixel dimensions
	xdotool windowsize "$slack_window" 1920 2128
	xdotool windowmove "$slack_window" 0 32

else
	echo "No Slack window found."
fi
firefox_window=$(xdotool search --onlyvisible --classname Navigator | head -n 1)
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
else
	echo "No Firefox window found."
fi
