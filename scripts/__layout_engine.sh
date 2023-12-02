#!/bin/bash

# Constants for screen dimensions
SCREEN_WIDTH=3840
SCREEN_HEIGHT=2160
HALF_WIDTH=$((SCREEN_WIDTH / 2))
HALF_HEIGHT=$((SCREEN_HEIGHT / 2))
# Add these new constants to account for the top bar and potential gaps
TOP_BAR_HEIGHT=5 # Adjust this value to match the height of your top bar
GAP=-10          # Gap to account for window decorations, adjust as needed

# Function to parse YAML and get layout configurations
parse_layout() {
	local layout_name=$1
	yq e ".layouts.${layout_name}.windows" -o=json layout_config.yaml
}

# Function to position a window
position_window() {
	local window_name=$1
	local position=$2

	# Find the window
	local window_id=$(xdotool search --onlyvisible --classname "$window_name" | head -n 1)

	if [[ -z "$window_id" ]]; then
		echo "Window '$window_name' not found."
		return
	fi

	echo "Positioning $window_name ($window_id) in $position"

	# Calculate position and size
	local x y width height

	case "$position" in
	# Adjust for the top bar height and gap in the top windows
	"1")
		x=$GAP
		y=$((TOP_BAR_HEIGHT + GAP))
		width=$((HALF_WIDTH - 2 * GAP))
		height=$((HALF_HEIGHT - TOP_BAR_HEIGHT - 2 * GAP))
		;;
	"2")
		x=$((HALF_WIDTH + GAP))
		y=$((TOP_BAR_HEIGHT + GAP))
		width=$((HALF_WIDTH - 2 * GAP))
		height=$((HALF_HEIGHT - TOP_BAR_HEIGHT - 2 * GAP))
		;;
	"3")
		x=$GAP
		y=$((HALF_HEIGHT + TOP_BAR_HEIGHT + GAP))
		width=$((HALF_WIDTH - 2 * GAP))
		height=$((HALF_HEIGHT - TOP_BAR_HEIGHT - 2 * GAP))
		;;
	"4")
		x=$((HALF_WIDTH + GAP))
		y=$((HALF_HEIGHT + TOP_BAR_HEIGHT + GAP))
		width=$((HALF_WIDTH - 2 * GAP))
		height=$((HALF_HEIGHT - TOP_BAR_HEIGHT - 2 * GAP))
		;;
	"1-2")
		x=$GAP
		y=$((TOP_BAR_HEIGHT + GAP))
		width=$((SCREEN_WIDTH - 2 * GAP))
		height=$((HALF_HEIGHT - TOP_BAR_HEIGHT - 2 * GAP))
		;;
	"3-4")
		x=$GAP
		y=$((HALF_HEIGHT + TOP_BAR_HEIGHT + GAP))
		width=$((SCREEN_WIDTH - 2 * GAP))
		height=$((HALF_HEIGHT - TOP_BAR_HEIGHT - 2 * GAP))
		;;
	"1-3")
		x=0
		y=0
		width=$HALF_WIDTH
		height=$SCREEN_HEIGHT
		;;
	"2-4")
		x=$HALF_WIDTH
		y=0
		width=$HALF_WIDTH
		height=$SCREEN_HEIGHT
		;;
	"max")
		x=0
		y=0
		width=$SCREEN_WIDTH
		height=$SCREEN_HEIGHT
		;;
	*)
		echo "Invalid position: $position"
		return
		;;
	esac

	# Position the window
	wmctrl -i -r "$window_id" -b remove,maximized_vert,maximized_horz
	xdotool windowmove "$window_id" $x $y
	xdotool windowsize "$window_id" $width $height
	xdotool windowactivate --sync "$window_id"
}

# Main
layout_name=$1
if [[ -z "$layout_name" ]]; then
	echo "No layout name provided."
	exit 1
fi

layout_config=$(parse_layout "$layout_name")

# Loop through each window configuration and position them
echo "$layout_config" | jq -c '.[]' | while IFS= read -r line; do
	window_name=$(echo $line | jq -r '.window')
	position=$(echo $line | jq -r '.position')
	position_window "$window_name" "$position"
done
