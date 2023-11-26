#!/bin/bash
LEFT_MARGIN=4
TOP_MARGIN_ZOOM=72    # Now for Zoom
TOP_MARGIN_SLACK=1133 # Now for Slack
WINDOW_WIDTH=3832
WINDOW_HEIGHT=1022

slack=$(xdotool search --onlyvisible --classname Slack | head -n 1)
zoom=$(xdotool search --onlyvisible --classname Zoom | head -n 1)

# Check if both Slack and Zoom windows are found
if [[ -n "$slack" && -n "$zoom" ]]; then
	echo "Both Slack and Zoom windows found. Arranging windows."

	# Position Zoom at the top
	wmctrl -i -r "$zoom" -b remove,maximized_vert,maximized_horz
	wmctrl -i -r "$zoom" -e 0,$LEFT_MARGIN,$TOP_MARGIN_ZOOM,$WINDOW_WIDTH,$WINDOW_HEIGHT

	# Position Slack at the bottom
	wmctrl -i -r "$slack" -b remove,maximized_vert,maximized_horz
	wmctrl -i -r "$slack" -e 0,$LEFT_MARGIN,$TOP_MARGIN_SLACK,$WINDOW_WIDTH,$WINDOW_HEIGHT

elif [[ -n "$zoom" ]]; then
	echo "Only Zoom window found. Positioning."
	wmctrl -i -r "$zoom" -b remove,maximized_vert,maximized_horz
	wmctrl -i -r "$zoom" -b add,maximized_vert,maximized_horz
	xdotool windowactivate --sync "$zoom"

elif [[ -n "$slack" ]]; then
	echo "Only Slack window found. Positioning."
	wmctrl -i -r "$slack" -b remove,maximized_vert,maximized_horz
	wmctrl -i -r "$slack" -b add,maximized_vert,maximized_horz
	xdotool windowactivate --sync "$slack"
else
	echo "No Slack or Zoom window found"
	/home/decoder/dev/dotfiles/scripts/__layout2.sh
	exit 0
fi
