#!/usr/bin/env bash

# Add source and line number wher running in debug mode: __run_with_xtrace.sh __layouts.sh
# Set new line and tab for word splitting
IFS=$'\n\t'

if [[ -z "$1" ]]; then
	echo "Usage: $0 {1|2|3|4|5|6|7|8}"
	exit 1
fi

#{{{ Utility Functions
maximize_window() {
	window="$1"
	wmctrl -i -r "$window" -b add,maximized_vert,maximized_horz
}
minimize_window() {
	window="$1"
	wmctrl -i -r "$window" -b remove,maximized_vert,maximized_horz
}
unmap_map_window() {
	window="$1"
	xdotool windowunmap "$window"
	xdotool windowmap "$window"
}
#}}}
max_alacritty() {
	# Get the ID of the first visible Alacritty window
	window=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)
	if [ -n "$window" ]; then
		# Unmaximize the window
		unmap_map_window "$window"
		maximize_window "$window"
		# wmctrl -r Alacritty -e 0,1920,0,-1,-1

		xdotool windowraise "$window"
		xdotool windowactivate --sync "$window"
	else
		echo "No Alacritty window found."
	fi
}
alacritty_firefox_vertical() {

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
		minimize_window "$firefox_window"
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
}
firefox_firefox_vertical() {

	# layout2.sh
	# Get the IDs of the first two Firefox windows across all workspaces
	firefox_windows=($(xdotool search --classname Navigator | head -n 2))
	if [ ${#firefox_windows[@]} -eq 2 ]; then
		# Iterate over the two windows and position them
		for i in 0 1; do
			window_id=${firefox_windows[$i]}
			minimize_window "$window_id"

			# Resize the window
			xdotool windowmap "$window_id"
			xdotool windowsize "$window_id" 1960 2168

			# Move the window to the specified coordinates
			if [ $i -eq 0 ]; then
				# Move the first window to the left side of the screen
				xdotool windowmove "$window_id" -20 12
				xdotool windowactivate --sync "$window_id"

			else
				# Move the second window to the right side of the screen
				xdotool windowmove "$window_id" 1900 12
				xdotool windowactivate --sync "$window_id"
			fi
		done
	elif [ ${#firefox_windows[@]} -eq 1 ]; then
		# Call __layout5.sh if only one Firefox window is found
		echo "Only one Firefox window found."
		max_firefox
	else
		echo "No Firefox windows found."
	fi
}
slack_firefox_vertical() {

	slack=$(xdotool search --onlyvisible --classname Slack | head -n 1)
	if [[ -z "${slack}" ]]; then
		echo "No Slack window found"
		alacritty_firefox_vertical
		exit 0
	fi

	# Get the ID of the first Firefox window across all workspaces
	slack_window=$(xdotool search --onlyvisible --classname Slack | head -n 1)
	if [ -n "$slack_window" ]; then

		minimize_window "$slack_window"

		xdotool windowmap "$slack_window"
		# Resize and move the window to the left side of the screen with exact pixel dimensions
		xdotool windowsize "$slack_window" 1920 2128
		xdotool windowmove "$slack_window" 0 32
		xdotool windowactivate --sync "$slack_window"

	else
		echo "No Slack window found."
	fi
	firefox_window=$(xdotool search --onlyvisible --classname Navigator | head -n 1)
	if [ -n "$firefox_window" ]; then
		# Unmaximize the window

		# Resize and move the Firefox window to the right side of the screen with exact pixel dimensions
		minimize_window "$firefox_window"
		# Assuming the screen resolution width is 3840, half of it is 1920
		# Adjust the height according to your screen resolution
		xdotool windowsize "$firefox_window" 1946 2154
		# Move the Firefox window to the right side of the screen
		# The x-coordinate is set to 1920 to position the window on the right half of the screen
		xdotool windowmove "$firefox_window" 1907 21
		xdotool windowactivate --sync "$firefox_window"
	else
		echo "No Firefox window found."
	fi
}
slack_alacritty_vertical() {

	slack=$(xdotool search --onlyvisible --classname Slack | head -n 1)
	if [[ -z "${slack}" ]]; then
		echo "No Slack window found"
		alacritty_firefox_vertical
		exit 0
	fi

	# Get the ID of the first Firefox window across all workspaces
	slack_window=$(xdotool search --onlyvisible --classname Slack | head -n 1)
	if [ -n "$slack_window" ]; then

		minimize_window "$slack_window"

		xdotool windowmap "$slack_window"
		# Resize and move the window to the left side of the screen with exact pixel dimensions
		xdotool windowsize "$slack_window" 1915 2092
		xdotool windowmove "$slack_window" 0 13
		xdotool windowactivate --sync "$slack_window"

	else
		echo "No Slack window found."
	fi
	# Get the ID of the first visible Alacritty window
	window=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)
	if [ -n "$window" ]; then
		# Unmaximize the window
		xdotool windowunmap "$window"
		# Resize the window
		xdotool windowmap "$window"
		# Resize and move the window to the left side of the screen with exact pixel dimensions
		xdotool windowsize "$window" 1920 2128
		xdotool windowmove "$window" 1907 21
		xdotool windowactivate --sync "$window"

	else
		echo "No Alacritty window found."
	fi
}
max_firefox() {

	# layout1.sh
	# Get the ID of the first visible Alacritty window
	window=$(xdotool search --onlyvisible --classname Navigator | head -n 1)
	if [ -n "$window" ]; then

		minimize_window "$window"
		# Resize the window
		xdotool windowmap "$window"
		# Resize and move the window to the left side of the screen with exact pixel dimensions
		maximize_window "$window"

		xdotool windowactivate --sync "$window"
		xdotool windowraise "$window"
	else
		echo "No Firefox window found."
	fi
}
# PROJECT: window_manager
zoom_alacritty_horizontal() {
	LEFT_MARGIN=4
	TOP_MARGIN_ZOOM=72    # Now for Zoom
	TOP_MARGIN_SLACK=1105 # Now for Slack
	WINDOW_WIDTH=3832
	WINDOW_HEIGHT=1022

	alacritty=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)
	zoom=$(xdotool search --onlyvisible --name 'Zoom Meeting' | head -n 1)
	slack=$(xdotool search --onlyvisible --classname Slack | head -n 1)

	# Check if Zoom or Slack windows are found along with alacritty
	if [[ -n "$alacritty" && -n "$zoom" ]]; then
		echo "Both alacritty and Zoom windows found. Arranging windows."
		# Position Zoom at the top
		minimize_window "$zoom"
		wmctrl -i -r "$zoom" -e 0,$LEFT_MARGIN,$TOP_MARGIN_ZOOM,$WINDOW_WIDTH,$WINDOW_HEIGHT
		xdotool windowactivate --sync "$zoom"

		# Position alacritty at the bottom
		minimize_window "$alacritty"
		wmctrl -i -r "$alacritty" -e 0,$LEFT_MARGIN,$TOP_MARGIN_SLACK,$WINDOW_WIDTH,1050
		xdotool windowactivate --sync "$alacritty"

	elif [[ -n "$zoom" ]]; then
		echo "Only Zoom window found. Positioning."
		minimize_window "$zoom"
		maximize_window "$zoom"
		xdotool windowactivate --sync "$zoom"

	elif [[ -n "$slack" ]]; then
		echo "Only Slack window found. Maximizing."
		minimize_window "$slack"
		maximize_window "$slack"
		xdotool windowactivate --sync "$slack"

	else
		echo "No Zoom or Slack window found. Exiting."
		alacritty_firefox_vertical
		exit 0
	fi
}
max_slack() {

	# Get the ID of the first visible slack window
	window=$(xdotool search --onlyvisible --classname Slack | head -n 1)
	if [ -n "$window" ]; then

		minimize_window "$window"
		# Resize the window
		xdotool windowmap "$window"
		# Resize and move the window to the left side of the screen with exact pixel dimensions
		maximize_window "$window"

		xdotool windowactivate --sync "$window"
		xdotool windowraise "$window"
	else
		echo "No Slack window found."
	fi
}
firefox_firefox_alacritty() {
	LEFT_MARGIN=4
	TOP_MARGIN_ZOOM=72    # Now for Zoom
	TOP_MARGIN_SLACK=1105 # Now for Slack
	WINDOW_WIDTH=3832
	WINDOW_HEIGHT=1022

	firefox_windows=($(xdotool search --classname Navigator | head -n 2))
	alacritty=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)

	firefox_windows=($(xdotool search --classname Navigator | head -n 2))
	if [ ${#firefox_windows[@]} -eq 2 ]; then
		# Iterate over the two windows and position them
		for i in 0 1; do
			window_id=${firefox_windows[$i]}
			minimize_window "$window_id"

			# Resize the window
			xdotool windowmap "$window_id"
			xdotool windowsize "$window_id" 1946 1094

			# Move the window to the left or right side of the screen
			if [ $i -eq 0 ]; then
				# Move the first window to the left side of the screen
				xdotool windowmove "$window_id" -13 21
				xdotool windowactivate --sync "$window_id"

			else
				# Move the second window to the right side of the screen
				xdotool windowmove "$window_id" 1910 0
				xdotool windowactivate --sync "$window_id"
			fi
		done
		# Position alacritty at the bottom
		minimize_window "$alacritty"
		wmctrl -i -r "$alacritty" -e 0,$LEFT_MARGIN,$TOP_MARGIN_SLACK,$WINDOW_WIDTH,1050
		xdotool windowactivate --sync "$alacritty"

	elif [ ${#firefox_windows[@]} -eq 1 ]; then
		# Call __layout5.sh if only one Firefox window is found
		echo "Only one Firefox window found."
		alacritty_firefox_vertical
	else
		echo "No Firefox windows found."
	fi
}

case $1 in
1) max_alacritty ;;
2) alacritty_firefox_vertical ;;
3) firefox_firefox_vertical ;;
4) slack_firefox_vertical ;;
5) max_firefox ;;
6) zoom_alacritty_horizontal ;;
7) max_slack ;;
8) firefox_firefox_alacritty ;;
9) slack_alacritty_vertical ;;
*)
	echo "Usage: $0 {1|2|3|4|5|6|7|8|9}"
	exit 1
	;;
esac
