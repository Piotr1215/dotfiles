#!/bin/bash

# Adjust with the actual Zoom window title
zoom_window_title="Zoom Cloud Meetings"

# Fetch the window ID for Zoom
zoom_window_id=$(wmctrl -l | grep "$zoom_window_title" | awk '{print $1}')

# Check if Zoom window is found
if [ -z "$zoom_window_id" ]; then
	echo "Zoom window not found."
	exit 1
fi

# Maximize the Zoom window
wmctrl -i -r "$zoom_window_id" -b add,maximized_vert,maximized_horz

# Wait for the window to maximize and the UI to settle
sleep 0.5

# Coordinates for the Google SSO button - replace with actual values
google_sso_button_x=1914
google_sso_button_y=1150

# Move mouse to the Google SSO button coordinates and click
xdotool mousemove $google_sso_button_x $google_sso_button_y click 1

echo "SSO Login process initiated."

# Wait for the window to maximize and the UI to settle
sleep 0.5

# Coordinates for the Google SSO button - replace with actual values
google_sso_button_x=1959
google_sso_button_y=1252

# Move mouse to the Google SSO button coordinates and click
xdotool mousemove $google_sso_button_x $google_sso_button_y click 1

echo "Google SSO button clicked."

sleep 5

# Adjust with a part of the Firefox window title that's consistent
firefox_window_title="Sign in - Google Accounts — Mozilla Firefox"

# Fetch the window ID for Firefox
firefox_window_id=$(wmctrl -l | grep "$firefox_window_title" | awk '{print $1}')

# Check if Firefox window is found
if [ -z "$firefox_window_id" ]; then
	echo "Firefox window not found."
	exit 1
fi

# Focus on the Firefox window
wmctrl -i -r "$firefox_window_id" -b add,maximized_vert,maximized_horz

# Wait for the window to focus
sleep 1

# Coordinates for the required button/link in Firefox - replace with actual values
firefox_button_x=1911
firefox_button_y=1118

# Move mouse to the button coordinates in Firefox and click
xdotool mousemove $firefox_button_x $firefox_button_y click 1

echo "Firefox interaction completed."
