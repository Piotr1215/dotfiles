#!/bin/bash

# layout1.sh
# Check if Alacritty is running
if pgrep -x "alacritty" >/dev/null; then
	# Get the ID of the first visible Alacritty window
	window=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)
	if [ -n "$window" ]; then
		# Unmaximize the window
		xdotool windowunmap "$window"
		sleep 0.2 # A short delay

		# Resize the window
		xdotool windowmap "$window"
		xdotool windowsize "$window" 45% 100%
	else
		echo "No Alacritty window found."
	fi
else
	# Launch Alacritty
	alacritty &
fi
