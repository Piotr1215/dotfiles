#!/bin/bash
LEFT_MARGIN=4
TOP_MARGIN_ZOOM=72    # Now for Zoom
TOP_MARGIN_SLACK=1105 # Now for Slack
WINDOW_WIDTH=3832
WINDOW_HEIGHT=1022

alacritty=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)
zoom=$(xdotool search --onlyvisible --class Zoom | head -n 1)
slack=$(xdotool search --onlyvisible --class Slack | head -n 1)

# Check if Zoom or Slack windows are found along with alacritty
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

elif [[ -n "$slack" ]]; then
	echo "Only Slack window found. Maximizing."
	wmctrl -i -r "$slack" -b remove,maximized_vert,maximized_horz
	wmctrl -i -r "$slack" -b add,maximized_vert,maximized_horz
	xdotool windowactivate --sync "$slack"

else
	echo "No Zoom or Slack window found. Exiting."
	/home/decoder/dev/dotfiles/scripts/__layout2.sh
	exit 0
fi
