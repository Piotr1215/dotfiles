#!/bin/bash
LEFT_MARGIN=4
TOP_MARGIN_ZOOM=72    # Now for Zoom
TOP_MARGIN_SLACK=1105 # Now for Slack
WINDOW_WIDTH=3832
WINDOW_HEIGHT=1022

alacritty=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)
zoom=$(xdotool search --onlyvisible --class Zoom | head -n 1)

# Check if both alacritty and Zoom windows are found
if [[ -n "$alacritty" && -n "$zoom" ]]; then
	echo "Both alacritty and Zoom windows found. Arranging windows."

	# Position Zoom at the top
	wmctrl -i -r "$zoom" -b remove,maximized_vert,maximized_horz
	wmctrl -i -r "$zoom" -e 0,$LEFT_MARGIN,$TOP_MARGIN_ZOOM,$WINDOW_WIDTH,$WINDOW_HEIGHT
	xdotool windowactivate --sync "$zoom"

	# Position alacritty at the bottom
	wmctrl -i -r "$alacritty" -b remove,maximized_vert,maximized_horz
	wmctrl -i -r "$alacritty" -e 0,$LEFT_MARGIN,$TOP_MARGIN_SLACK,$WINDOW_WIDTH,1050
	xdotool windowactivate --sync "$alacritty"

elif [[ -n "$zoom" ]]; then
	echo "Only Zoom window found. Positioning."
	wmctrl -i -r "$zoom" -b remove,maximized_vert,maximized_horz
	wmctrl -i -r "$zoom" -b add,maximized_vert,maximized_horz
	xdotool windowactivate --sync "$zoom"

elif [[ -n "$alacritty" ]]; then
	echo "Only alacritty window found. Positioning."
	wmctrl -i -r "$alacritty" -b remove,maximized_vert,maximized_horz
	wmctrl -i -r "$alacritty" -b add,maximized_vert,maximized_horz
	xdotool windowactivate --sync "$alacritty"
else
	echo "No alacritty or Zoom window found"
	/home/decoder/dev/dotfiles/scripts/__layout2.sh
	exit 0
fi
