#!/usr/bin/env bash

# Add source and line number wher running in debug mode: __run_with_xtrace.sh __layouts.sh
# Set new line and tab for word splitting
IFS=$'\n\t'

if [[ -z "$1" ]]; then
	echo "Usage: $0 {1|2|3|4|5|6|7|8|9|10}"
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

# PROJECT: alacritty_transparency
max_alacritty() {
	# Get the ID of the first visible Alacritty window
	window=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)
	if [ -n "$window" ]; then
		# Minimize all windows except Alacritty and Zoom with sync
		for win_id in $(xdotool search --onlyvisible --name ".*"); do
			window_class=$(xprop -id "$win_id" WM_CLASS 2>/dev/null)
			if [ "$win_id" != "$window" ] && ! echo "$window_class" | grep -qi "zoom"; then
				xdotool windowminimize --sync "$win_id"
			fi
		done
		
		# Handle the Alacritty window
		minimize_window "$window"
		xdotool windowmap --sync "$window"
		maximize_window "$window"
		xdotool windowraise --sync "$window"
		xdotool windowactivate --sync "$window"
	else
		echo "No Alacritty window found."
	fi
}

alacritty_firefox_vertical() {
	# Get screen dimensions
	screen_size=$(xdpyinfo | grep dimensions | awk '{print $2}')
	screen_width=$(echo $screen_size | cut -d'x' -f1)
	half_width=$((screen_width / 2))

	# Get the ID of the first visible Alacritty window
	window=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)
	if [ -n "$window" ]; then
		# Handle Alacritty window - left side
		minimize_window "$window"
		# Use sync flag to wait for window to be mapped/visible
		xdotool windowmap --sync "$window"
		# Combine size and move operations with sync
		xdotool windowsize --sync "$window" $half_width 2128
		xdotool windowmove --sync "$window" 0 32
		xdotool windowactivate --sync "$window"
		xdotool windowraise --sync "$window"
	else
		echo "No Alacritty window found."
	fi

	# Get the ID of the first Firefox window across all workspaces
	firefox_window=$(xdotool search --classname Navigator | head -n 1)
	if [ -n "$firefox_window" ]; then
		# First, maximize and wait for completion
		wmctrl -i -r "$firefox_window" -b add,maximized_vert,maximized_horz
		# Then unmaximize and wait for completion
		xdotool windowactivate --sync "$firefox_window"
		wmctrl -i -r "$firefox_window" -b remove,maximized_vert,maximized_horz
		
		# Now resize and position Firefox exactly at the second half of the screen
		xdotool windowsize --sync "$firefox_window" $half_width 2154
		xdotool windowmove --sync "$firefox_window" $half_width 21
		
		# Force focus and ensure it's on top
		xdotool windowactivate --sync "$firefox_window"
		xdotool windowraise "$firefox_window"
	else
		echo "No Firefox window found."
	fi
}
firefox_firefox_vertical() {
	# Minimize any visible Alacritty windows
	alacritty_window=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)
	if [ -n "$alacritty_window" ]; then
		xdotool windowminimize --sync "$alacritty_window"
	fi

	# Get the IDs of the first two Firefox windows
	firefox_windows=($(xdotool search --classname Navigator | head -n 2))

	if [ ${#firefox_windows[@]} -eq 2 ]; then
		for i in 0 1; do
			window_id=${firefox_windows[$i]}

			# First, remove window decorations using window manager properties
			wmctrl -i -r "$window_id" -b add,maximized_vert,maximized_horz
			xdotool windowactivate --sync "$window_id"
			wmctrl -i -r "$window_id" -b remove,maximized_vert,maximized_horz

			# Fixing the overlap in the middle
			if [ $i -eq 0 ]; then
				# Left window - reduce width to eliminate overlap
				xdotool windowsize --sync "$window_id" 1870 2180
				xdotool windowmove --sync "$window_id" -26 24
			else
				# Right window - maintain right edge position
				xdotool windowsize --sync "$window_id" 1971 2180
				xdotool windowmove --sync "$window_id" 1920 24
			fi

			# Ensure proper activation and raise to top
			xdotool windowactivate --sync "$window_id"
			xdotool windowraise --sync "$window_id"
		done
	elif [ ${#firefox_windows[@]} -eq 1 ]; then
		echo "Only one Firefox window found."
		max_firefox
	else
		echo "No Firefox windows found."
	fi
}
slack_firefox_vertical() {
	# Find both windows upfront
	slack=$(xdotool search --onlyvisible --classname Slack | head -n 1)
	if [[ -z "${slack}" ]]; then
		echo "No Slack window found"
		alacritty_firefox_vertical
		exit 0
	fi
	
	firefox_window=$(xdotool search --classname Navigator | head -n 1)
	if [ -z "$firefox_window" ]; then
		echo "No Firefox window found."
		exit 0
	fi
	
	# Fix for slowdown: Put Firefox on current desktop first
	xdotool windowactivate --sync "$firefox_window"
	wmctrl -i -r "$firefox_window" -b remove,maximized_vert,maximized_horz
	
	# Position and resize Firefox without --sync flags to avoid delays
	xdotool windowsize "$firefox_window" 1946 2154
	xdotool windowmove "$firefox_window" 1907 21
	
	# Position and resize Slack without --sync flags to avoid delays
	wmctrl -i -r "$slack" -b remove,maximized_vert,maximized_horz
	xdotool windowsize "$slack" 1920 2128
	xdotool windowmove "$slack" 0 32
	
	# Final activation and raise
	xdotool windowactivate "$slack"
	sleep 0.2
	xdotool windowactivate "$firefox_window"
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
		xdotool windowmap --sync "$slack_window"
		
		# Resize and move the window to the left side of the screen with exact pixel dimensions
		xdotool windowsize --sync "$slack_window" 1915 2092
		xdotool windowmove --sync "$slack_window" 0 13
		xdotool windowactivate --sync "$slack_window"
		xdotool windowraise --sync "$slack_window"
	else
		echo "No Slack window found."
	fi
	
	# Get the ID of the first visible Alacritty window
	window=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)
	if [ -n "$window" ]; then
		minimize_window "$window"
		xdotool windowmap --sync "$window"
		
		# Resize and move the window to the right side of the screen with exact pixel dimensions
		xdotool windowsize --sync "$window" 1920 2128
		xdotool windowmove --sync "$window" 1907 21
		xdotool windowactivate --sync "$window"
		xdotool windowraise --sync "$window"
	else
		echo "No Alacritty window found."
	fi
}
max_firefox() {
	# layout1.sh
	# Get the ID of the first visible Firefox window
	window=$(xdotool search --onlyvisible --classname Navigator | head -n 1)
	if [ -n "$window" ]; then
		minimize_window "$window"
		# Map window with sync
		xdotool windowmap --sync "$window"
		# Maximize window
		maximize_window "$window"
		# Ensure window is active and on top
		xdotool windowactivate --sync "$window"
		xdotool windowraise --sync "$window"
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
	zoom=$(xdotool search --onlyvisible --name 'Meeting' | head -n 1)
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
		# Map window with sync
		xdotool windowmap --sync "$window"
		# Maximize window
		maximize_window "$window"
		# Ensure window is active and on top
		xdotool windowactivate --sync "$window"
		xdotool windowraise --sync "$window"
	else
		echo "No Slack window found."
	fi
}
firefox_firefox_alacritty() {
	# Get screen dimensions
	screen_size=$(xdpyinfo | grep dimensions | awk '{print $2}')
	screen_width=$(echo $screen_size | cut -d'x' -f1)
	half_width=$((screen_width / 2))

	# Calculate dimensions
	firefox_height=1094
	firefox_y=21
	alacritty_y=$((firefox_y + firefox_height)) # Position Alacritty right after Firefox ends
	alacritty_height=1028                       # Adjusted to fit remaining space

	# Get window IDs
	firefox_windows=($(xdotool search --classname Navigator | head -n 2))
	alacritty=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)

	if [ ${#firefox_windows[@]} -eq 2 ] && [ -n "$alacritty" ]; then
		# Handle Firefox windows first (top split)
		for i in 0 1; do
			window_id=${firefox_windows[$i]}

			# Handle window decorations
			wmctrl -i -r "$window_id" -b add,maximized_vert,maximized_horz
			xdotool windowactivate --sync "$window_id"
			wmctrl -i -r "$window_id" -b remove,maximized_vert,maximized_horz

			# Set size for top half with sync
			xdotool windowsize --sync "$window_id" $half_width $firefox_height

			# Position windows with sync
			if [ $i -eq 0 ]; then
				# Left window
				xdotool windowmove --sync "$window_id" 0 $firefox_y
			else
				# Right window
				xdotool windowmove --sync "$window_id" $half_width $firefox_y
			fi

			xdotool windowactivate --sync "$window_id"
			xdotool windowraise --sync "$window_id"
		done

		# Handle Alacritty (bottom)
		wmctrl -i -r "$alacritty" -b add,maximized_vert,maximized_horz
		xdotool windowactivate --sync "$alacritty"
		wmctrl -i -r "$alacritty" -b remove,maximized_vert,maximized_horz

		# Position Alacritty across bottom with sync
		xdotool windowsize --sync "$alacritty" $screen_width $alacritty_height
		xdotool windowmove --sync "$alacritty" 0 $alacritty_y
		xdotool windowactivate --sync "$alacritty"
		xdotool windowraise --sync "$alacritty"

	elif [ ${#firefox_windows[@]} -eq 1 ]; then
		echo "Only one Firefox window found."
		alacritty_firefox_vertical
	else
		echo "No Firefox windows found."
	fi
}

alacritty_resize_9_16() {
	# Calculate the dimensions for a 9:16 aspect ratio.
	# Setting height to 1800 pixels
	local height=2100
	local width=$((height * 9 / 16))

	# Get the ID of the first visible Alacritty window
	local window=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)
	if [ -n "$window" ]; then
		# Unmaximize the window if it is maximized
		minimize_window "$window"

		# Resize and move the window, adjust the position from the edges
		xdotool windowsize "$window" $width $height
		xdotool windowmove "$window" 50 50
		xdotool windowactivate --sync "$window"
	else
		echo "No Alacritty window found."
	fi
}

claude_alacritty_vertical() {
	# Get screen dimensions
	screen_size=$(xdpyinfo | grep dimensions | awk '{print $2}')
	screen_width=$(echo $screen_size | cut -d'x' -f1)
	half_width=$((screen_width / 2))

	# Get the ID of the first visible Claude window
	claude_window=$(xdotool search --onlyvisible --class "Claude" 2>/dev/null || xdotool search --onlyvisible --name "Claude" 2>/dev/null)
	if [ -n "$claude_window" ]; then
		# Handle Claude window - left side
		minimize_window "$claude_window"
		# Use sync flag to wait for window to be mapped/visible
		xdotool windowmap --sync "$claude_window"
		# Combine size and move operations with sync
		xdotool windowsize --sync "$claude_window" $half_width 2128
		xdotool windowmove --sync "$claude_window" 0 32
		xdotool windowactivate --sync "$claude_window"
		xdotool windowraise "$claude_window"
	else
		echo "No Claude window found."
	fi

	# Get the ID of the first Alacritty window
	alacritty_window=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)
	if [ -n "$alacritty_window" ]; then
		# First, maximize and wait for completion
		wmctrl -i -r "$alacritty_window" -b add,maximized_vert,maximized_horz
		# Then unmaximize and wait for completion
		xdotool windowactivate --sync "$alacritty_window"
		wmctrl -i -r "$alacritty_window" -b remove,maximized_vert,maximized_horz
		
		# Now resize and position Alacritty exactly at the second half of the screen
		xdotool windowsize --sync "$alacritty_window" $half_width 2154
		xdotool windowmove --sync "$alacritty_window" $half_width 21
		
		# Force focus and ensure it's on top
		xdotool windowactivate --sync "$alacritty_window"
		xdotool windowraise "$alacritty_window"
	else
		echo "No Alacritty window found."
	fi
}

firefox_claude_vertical() {
	# Minimize any visible Alacritty windows
	alacritty_window=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)
	if [ -n "$alacritty_window" ]; then
		xdotool windowminimize --sync "$alacritty_window"
	fi

	# Get the ID of the first Firefox window
	firefox_window=$(xdotool search --onlyvisible --classname Navigator | head -n 1)
	if [ -n "$firefox_window" ]; then
		# First, remove window decorations using window manager properties
		wmctrl -i -r "$firefox_window" -b add,maximized_vert,maximized_horz
		xdotool windowactivate --sync "$firefox_window"
		wmctrl -i -r "$firefox_window" -b remove,maximized_vert,maximized_horz

		# Use the same positioning as in firefox_firefox_vertical for left window
		xdotool windowsize --sync "$firefox_window" 1870 2180
		xdotool windowmove --sync "$firefox_window" -26 24
		xdotool windowactivate --sync "$firefox_window"
		xdotool windowraise "$firefox_window"
	else
		echo "No Firefox window found."
	fi

	# Get the ID of the first Claude window
	claude_window=$(xdotool search --onlyvisible --class "Claude" 2>/dev/null || xdotool search --onlyvisible --name "Claude" 2>/dev/null)
	if [ -n "$claude_window" ]; then
		# First, maximize and wait for completion
		wmctrl -i -r "$claude_window" -b add,maximized_vert,maximized_horz
		# Then unmaximize and wait for completion
		xdotool windowactivate --sync "$claude_window"
		wmctrl -i -r "$claude_window" -b remove,maximized_vert,maximized_horz
		
		# Use the same positioning as in firefox_firefox_vertical for right window
		xdotool windowsize --sync "$claude_window" 1971 2180
		xdotool windowmove --sync "$claude_window" 1920 24
		
		# Force focus and ensure it's on top
		xdotool windowactivate --sync "$claude_window"
		xdotool windowraise "$claude_window"
	else
		echo "No Claude window found."
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
10) alacritty_resize_9_16 ;;
11) claude_alacritty_vertical ;;
12) firefox_claude_vertical ;;
*)
	echo "Usage: $0 {1|2|3|4|5|6|7|8|9|10|11|12}"
	exit 1
	;;
esac
