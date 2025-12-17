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

# Visual focus indicator - flash window or change opacity briefly
indicate_focus() {
	local window="$1"
	local window_name="${2:-Window}"
	
	# Method 1: Brief opacity change (if compositor available)
	if command -v xprop >/dev/null 2>&1; then
		# Set temporary opacity for flash effect
		xprop -id "$window" -f _NET_WM_WINDOW_OPACITY 32c -set _NET_WM_WINDOW_OPACITY 0xdddddddd
		sleep 0.1
		xprop -id "$window" -remove _NET_WM_WINDOW_OPACITY
	fi
	
	# Method 2: Show subtle notification (optional)
	# notify-send -t 500 -u low "Focus: $window_name" >/dev/null 2>&1 &
}

# Dim inactive Alacritty windows
dim_inactive_alacritty() {
	local active_window="$1"
	for win_id in $(xdotool search --onlyvisible --classname Alacritty); do
		if [ "$win_id" != "$active_window" ]; then
			# Set 85% opacity for inactive Alacritty windows
			xprop -id "$win_id" -f _NET_WM_WINDOW_OPACITY 32c -set _NET_WM_WINDOW_OPACITY 0xe6666666
		else
			# Full opacity for active window
			xprop -id "$win_id" -remove _NET_WM_WINDOW_OPACITY
		fi
	done
}

# Reset all window opacity to normal
reset_all_opacity() {
	for win_id in $(xdotool search --onlyvisible --name ".*"); do
		xprop -id "$win_id" -remove _NET_WM_WINDOW_OPACITY 2>/dev/null
	done
}

# Dim ALL inactive windows (Firefox, Alacritty, etc)
dim_all_inactive_windows() {
	local active_window="$1"
	
	# First reset all windows to full opacity
	reset_all_opacity
	
	# Then dim only the inactive ones
	for win_id in $(xdotool search --onlyvisible --name ".*"); do
		# Skip desktop, panels, etc
		window_class=$(xprop -id "$win_id" WM_CLASS 2>/dev/null)
		
		# Check if it's a regular application window
		if echo "$window_class" | grep -qE "firefox|Navigator|librewolf|Librewolf|Alacritty|Slack|slack|Code|code"; then
			if [ "$win_id" != "$active_window" ]; then
				# Dim inactive windows to 85% opacity
				xprop -id "$win_id" -f _NET_WM_WINDOW_OPACITY 32c -set _NET_WM_WINDOW_OPACITY 0xe6666666
			fi
			# Active window stays at full opacity (no action needed after reset)
		fi
	done
}
# Get browser window (Firefox or LibreWolf)
get_browser_windows() {
	xdotool search --classname Navigator 2>/dev/null
	xdotool search --classname librewolf 2>/dev/null
}
get_visible_browser_window() {
	xdotool search --onlyvisible --classname Navigator 2>/dev/null | head -n 1
	xdotool search --onlyvisible --classname librewolf 2>/dev/null | head -n 1
}
#}}}

# PROJECT: alacritty_transparency
max_alacritty() {
	# Get the ID of the first visible Alacritty window
	window=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)
	if [ -n "$window" ]; then
		# Minimize all windows except Alacritty, Zoom, and MPV with sync
		for win_id in $(xdotool search --onlyvisible --name ".*"); do
			window_class=$(xprop -id "$win_id" WM_CLASS 2>/dev/null)
			window_name=$(xprop -id "$win_id" WM_NAME 2>/dev/null | cut -d'"' -f2)
			if [ "$win_id" != "$window" ] && ! echo "$window_class" | grep -qi "zoom" && ! echo "$window_name" | grep -qi "mpv\|\.mp4\|\.mkv\|\.avi\|\.mov\|\.webm"; then
				xdotool windowminimize --sync "$win_id"
			fi
		done
		
		# Handle the Alacritty window
		minimize_window "$window"
		xdotool windowmap --sync "$window"
		maximize_window "$window"
		xdotool windowraise "$window"
		xdotool windowactivate --sync "$window"
		
		# Apply dimming to ALL inactive windows
		dim_all_inactive_windows "$window"
		
		# Optional: Flash to indicate focus
		# indicate_focus "$window" "Alacritty"
	else
		echo "No Alacritty window found."
	fi
}

alacritty_firefox_vertical() {
	# Get screen dimensions
	screen_size=$(xdpyinfo | grep dimensions | awk '{print $2}')
	screen_width=$(echo $screen_size | cut -d'x' -f1)
	half_width=$((screen_width / 2))

	# Get the ID of the first browser window across all workspaces
	firefox_window=$(get_browser_windows | head -n 1)
	if [ -n "$firefox_window" ]; then
		# First, maximize and then unmaximize
		wmctrl -i -r "$firefox_window" -b add,maximized_vert,maximized_horz
		xdotool windowactivate "$firefox_window"
		wmctrl -i -r "$firefox_window" -b remove,maximized_vert,maximized_horz
		
		# Position Firefox on the left side using the same values as in firefox_firefox_vertical
		xdotool windowsize "$firefox_window" 1870 2180
		xdotool windowmove "$firefox_window" -26 24
	else
		echo "No Firefox window found."
		return 1
	fi

	# Get the ID of the first visible Alacritty window
	alacritty_window=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)
	if [ -n "$alacritty_window" ]; then
		# Handle Alacritty window - right side
		minimize_window "$alacritty_window"
		# Map window without sync
		xdotool windowmap "$alacritty_window"
		# Position Alacritty on the right side without sync flags
		xdotool windowsize "$alacritty_window" 1971 2180
		xdotool windowmove "$alacritty_window" 1920 24
	else
		echo "No Alacritty window found."
		return 1
	fi
	
	# Set focus to Alacritty using standard methods without sync
	xdotool windowactivate "$alacritty_window"
	xdotool windowraise "$alacritty_window"
}
firefox_firefox_vertical() {
	# Minimize any visible Alacritty windows
	alacritty_window=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)
	if [ -n "$alacritty_window" ]; then
		xdotool windowminimize --sync "$alacritty_window"
	fi

	# Get the IDs of the first two browser windows
	firefox_windows=($(get_browser_windows | head -n 2))

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
			xdotool windowraise "$window_id"
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
	
	firefox_window=$(get_browser_windows | head -n 1)
	if [ -z "$firefox_window" ]; then
		echo "No browser window found."
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
	# Fix for performance: Remove unnecessary --sync flags which cause delays

	slack=$(xdotool search --onlyvisible --classname Slack | head -n 1)
	if [[ -z "${slack}" ]]; then
		echo "No Slack window found"
		alacritty_firefox_vertical
		exit 0
	fi

	# Get the ID of the first Slack window 
	slack_window=$(xdotool search --onlyvisible --classname Slack | head -n 1)
	if [ -n "$slack_window" ]; then
		minimize_window "$slack_window"
		xdotool windowmap "$slack_window"
		
		# Resize and move the window to the left side of the screen without --sync flags
		xdotool windowsize "$slack_window" 1915 2092
		xdotool windowmove "$slack_window" 0 13
		xdotool windowactivate "$slack_window"
		xdotool windowraise "$slack_window"
	else
		echo "No Slack window found."
	fi
	
	# Get the ID of the first visible Alacritty window
	window=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)
	if [ -n "$window" ]; then
		minimize_window "$window"
		xdotool windowmap "$window"
		
		# Resize and move the window to the right side of the screen without --sync flags
		xdotool windowsize "$window" 1920 2128
		xdotool windowmove "$window" 1907 21
		xdotool windowactivate "$window"
		xdotool windowraise "$window"
	else
		echo "No Alacritty window found."
	fi
}
max_firefox() {
	# layout1.sh
	# Get the ID of the first visible browser window
	window=$(get_visible_browser_window | head -n 1)
	if [ -n "$window" ]; then
		minimize_window "$window"
		# Map window with sync
		xdotool windowmap --sync "$window"
		# Maximize window
		maximize_window "$window"
		# Ensure window is active and on top
		xdotool windowactivate --sync "$window"
		xdotool windowraise "$window"
		
		# Apply dimming to ALL inactive windows
		dim_all_inactive_windows "$window"
	else
		echo "No Firefox window found."
	fi
}
# PROJECT: window_manager
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
		xdotool windowraise "$window"
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
	firefox_windows=($(get_browser_windows | head -n 2))
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
			xdotool windowraise "$window_id"
		done

		# Handle Alacritty (bottom)
		wmctrl -i -r "$alacritty" -b add,maximized_vert,maximized_horz
		xdotool windowactivate --sync "$alacritty"
		wmctrl -i -r "$alacritty" -b remove,maximized_vert,maximized_horz

		# Position Alacritty across bottom with sync
		xdotool windowsize --sync "$alacritty" $screen_width $alacritty_height
		xdotool windowmove --sync "$alacritty" 0 $alacritty_y
		xdotool windowactivate --sync "$alacritty"
		xdotool windowraise "$alacritty"

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

chatgpt_alacritty_vertical() {
	# Get screen dimensions
	screen_size=$(xdpyinfo | grep dimensions | awk '{print $2}')
	screen_width=$(echo $screen_size | cut -d'x' -f1)
	half_width=$((screen_width / 2))

	# Check if browser is running
	firefox_window=$(get_browser_windows | head -n 1)
	
	# PROJECT: brotab
	# Check if Claude tab exists using brotab
	claude_tab_id=""
	if [ -n "$firefox_window" ]; then
		# Use brotab to find Claude tab
		claude_tab_id=$(brotab list 2>/dev/null | grep "https://chatgpt\.com" | head -n 1 | cut -f1)
	fi
	
	if [ -n "$claude_tab_id" ]; then
		# Claude tab exists, activate it directly using brotab
		brotab activate "$claude_tab_id" 2>/dev/null
		# Also ensure Firefox window is focused
		xdotool windowactivate "$firefox_window"
	else
		# ChatGPT not open, open it in browser
		if [ -n "$firefox_window" ]; then
			# Browser is running, open in new tab
			flatpak run io.gitlab.librewolf-community "https://chatgpt.com" 2>/dev/null &
		else
			# No browser running, start it with ChatGPT
			flatpak run io.gitlab.librewolf-community "https://chatgpt.com" 2>/dev/null &
			sleep 2  # Give browser time to start
			firefox_window=$(get_browser_windows | head -n 1)
		fi
		
		# Brief wait for tab to load
		sleep 0.5
	fi

	if [ -n "$firefox_window" ]; then
		# First, maximize and then unmaximize
		wmctrl -i -r "$firefox_window" -b add,maximized_vert,maximized_horz
		xdotool windowactivate "$firefox_window"
		wmctrl -i -r "$firefox_window" -b remove,maximized_vert,maximized_horz
		
		# Position Firefox on the left side using the same values as in alacritty_firefox_vertical
		xdotool windowsize "$firefox_window" 1870 2180
		xdotool windowmove "$firefox_window" -26 24
	else
		echo "No Firefox window found."
		return 1
	fi

	# Get the ID of the first visible Alacritty window
	alacritty_window=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)
	if [ -n "$alacritty_window" ]; then
		# Handle Alacritty window - right side
		minimize_window "$alacritty_window"
		# Map window without sync
		xdotool windowmap "$alacritty_window"
		# Position Alacritty on the right side without sync flags
		xdotool windowsize "$alacritty_window" 1971 2180
		xdotool windowmove "$alacritty_window" 1920 24
	else
		echo "No Alacritty window found."
		return 1
	fi
	
	# Set focus to Alacritty using standard methods without sync
	xdotool windowactivate "$alacritty_window"
	xdotool windowraise "$alacritty_window"
}


case $1 in
1) max_alacritty ;;
2) alacritty_firefox_vertical ;;
3) firefox_firefox_vertical ;;
4) slack_firefox_vertical ;;
5) max_firefox ;;
6) max_slack ;;
7) firefox_firefox_alacritty ;;
8) slack_alacritty_vertical ;;
9) alacritty_resize_9_16 ;;
10) chatgpt_alacritty_vertical ;;
*)
	echo "Usage: $0 {1|2|3|4|5|6|7|8|9|10}"
	exit 1
	;;
esac
