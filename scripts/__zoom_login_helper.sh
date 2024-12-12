#!/bin/bash

export DISPLAY=:1

# Function to check if we're already logged into Zoom
check_zoom_login() {
	# Use awk to match windows that start with Zoom
	# and don't contain login-related terms
	local zoom_windows=$(wmctrl -l | awk '$NF ~ /^Zoom/ && !/Sign In/ && !/Login/')
	if [ -n "$zoom_windows" ]; then
		echo "Zoom is already running and logged in"
		return 0
	fi
	return 1
}

# Function to wait for a window with specified title
wait_for_window() {
	local title="$1"
	local max_attempts=20 # 10 seconds max (20 * 0.5s)
	local attempt=0

	while [ $attempt -lt $max_attempts ]; do
		if wmctrl -l | grep -q "$title"; then
			return 0
		fi
		attempt=$((attempt + 1))
		sleep 0.5
	done
	return 1
}

# Exit if already logged in
if check_zoom_login; then
	echo "Zoom is already running and logged in. No action needed."
	exit 0
fi

# Launch Zoom
zoom &
sleep 1.5

# Adjust with the actual Zoom window title
zoom_window_title="Zoom Workplace"
# Fetch the window ID for Zoom
zoom_window_id=$(wmctrl -l | grep "$zoom_window_title" | awk '{print $1}')

# Maximize the Zoom window
wmctrl -i -r "$zoom_window_id" -b add,maximized_vert,maximized_horz

# Wait for the window to maximize and the UI to settle
sleep 1

# Click SSO buttons in Zoom
xdotool mousemove 1914 1150 click 1
echo "SSO Login process initiated."
sleep 1
xdotool mousemove 1959 1252 click 1
echo "Google SSO button clicked."

# Wait for Firefox window to open
firefox_window_title="Anmelden – Google Konten — Mozilla Firefox"
echo "Waiting for Firefox login window..."
if ! wait_for_window "$firefox_window_title"; then
	echo "Firefox login window did not appear in time."
	exit 1
fi

# Get Firefox window ID and focus it
firefox_window_id=$(wmctrl -l | grep "$firefox_window_title" | awk '{print $1}')
wmctrl -i -r "$firefox_window_id" -b add,maximized_vert,maximized_horz
wmctrl -i -a "$firefox_window_id"
sleep 1

# Click email selection with correct coordinates
xdotool mousemove 2068 1061 click 1
echo "Clicked email selection"

# Wait for second Firefox window (Sign in)
firefox_signin_title="Sign in - Google Accounts — Mozilla Firefox"
echo "Waiting for Firefox sign in window..."
if ! wait_for_window "$firefox_signin_title"; then
	echo "Firefox sign in window did not appear in time."
	exit 1
fi

# Focus sign in window
firefox_signin_id=$(wmctrl -l | grep "$firefox_signin_title" | awk '{print $1}')
wmctrl -i -r "$firefox_signin_id" -b add,maximized_vert,maximized_horz
wmctrl -i -a "$firefox_signin_id"
sleep 1

# Click continue button with correct coordinates
xdotool mousemove 2293 1258 click 1
echo "Clicked continue button"

# Wait for final Firefox window
echo "Waiting for final Firefox window..."
final_firefox_title="Login with Google - Zoom — Mozilla Firefox"
if ! wait_for_window "$final_firefox_title"; then
	echo "Final Firefox window did not appear in time."
	exit 1
fi

# Get final window ID and close it
final_window_id=$(wmctrl -l | grep "$final_firefox_title" | awk '{print $1}')
wmctrl -i -a "$final_window_id"
sleep 0.5
xdotool key super+q
echo "Closed final Firefox window"
