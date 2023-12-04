#!/bin/bash

# PROJECT: zoom-monitor
echo "$(date): Script started" >>/home/decoder/zoom_monitor.log

# Initialize a flag to track login status
login_initiated=0

# Loop to check for Zoom window
while true; do
	echo "$(date): Checking for Zoom window..." >>/home/decoder/zoom_monitor.log

	if wmctrl -l | grep -q "Zoom Cloud Meetings"; then
		echo "$(date): Zoom window found." >>/home/decoder/zoom_monitor.log

		if [ "$login_initiated" -eq 0 ]; then
			sleep 3
			echo "$(date): Login not initiated, displaying Zenity prompt." >>/home/decoder/zoom_monitor.log
			zenity --question --text="Do you want to autologin to Zoom?" --display=":1" \
				--ok-label="Yes" --cancel-label="No" \
				--width=200 --height=100

			# Check the exit status of zenity
			case $? in
			0) # User clicked "Acknowledged"
				echo "$(date): User agreed to autologin. Executing login script." >>/home/decoder/zoom_monitor.log

				# Adjust with the actual Zoom window title
				zoom_window_title="Zoom Cloud Meetings"

				# Fetch the window ID for Zoom
				zoom_window_id=$(xdotool search --name "$zoom_window_title")

				# Check if Zoom window is found
				if [ -z "$zoom_window_id" ]; then
					echo "Zoom window not found."
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
				# close firefox window
				sleep 3
				wmctrl -i -c "$firefox_window_id"

				login_initiated=1
				;;
			1) # User declined autologin
				echo "$(date): User declined autologin." >>/home/decoder/zoom_monitor.log
				;;
			*) # Any other exit code means an error or unexpected closure
				break
				;;
			esac

		else
			echo "$(date): Login already initiated, skipping Zenity prompt." >>/home/decoder/zoom_monitor.log
		fi
	else
		echo "$(date): Zoom window not found." >>/home/decoder/zoom_monitor.log
		login_initiated=0
	fi
	sleep 5 # Check every 10 seconds
done
