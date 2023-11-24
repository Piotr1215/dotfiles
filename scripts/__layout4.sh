#!/bin/bash
UPPER_SCREEN_HEIGHT=11
MIDDLE_SCREEN_POING=1920
LEFT_SCREEN_CORNER=0
HALF_SCREEN_WIDTH=1930
FULL_SCREEN_WIDTH=3860
# layout3.sh
# Check if Alacritty is running
if pgrep -x "alacritty" >/dev/null; then
	# Get the ID of the first visible Alacritty window
	window=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)
	if [ -n "$window" ]; then
		wmctrl -i -r "$window" -b remove,maximized_vert,maximized_horz

		wmctrl -i -r "$window" -e 0,$LEFT_SCREEN_CORNER,0,$HALF_SCREEN_WIDTH,1080
	else
		echo "No Alacritty window found."
	fi

	# Get the ID of the first Firefox window across all workspaces
	slack_window=$(xdotool search --onlyvisible --classname Slack | head -n 1)
	if [ -n "$slack_window" ]; then

		wmctrl -i -r "$slack_window" -b remove,maximized_vert,maximized_horz

		# wmctrl -i -r ID -e 0,left,up,width,height
		wmctrl -i -r "$slack_window" -e 0,$LEFT_SCREEN_CORNER,1115,$FULL_SCREEN_WIDTH,1010

	else
		echo "No Slack window found."
	fi
	# Get the ID of the first Firefox window across all workspaces
	firefox_window=$(xdotool search --onlyvisible --classname Navigator | head -n 1)
	if [ -n "$firefox_window" ]; then
		# Unmaximize the window

		# Resize and move the Firefox window to the right side of the screen with exact pixel dimensions
		wmctrl -i -r "$firefox_window" -b remove,maximized_vert,maximized_horz

		# wmctrl -i -r ID -e 0,left,up,width,height
		wmctrl -i -r "$firefox_window" -e 0,$MIDDLE_SCREEN_POING,0,$HALF_SCREEN_WIDTH,1108
	else
		echo "No Firefox window found."
	fi

else
	# Launch Alacritty
	alacritty &
fi
