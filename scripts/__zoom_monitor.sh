#!/usr/bin/env bash
# PROJECT: zoom-monitor with notifications

# Log file location
LOG_FILE="/home/decoder/zoom_monitor.log"

# Function to log messages with timestamps
log_message() {
	echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >>"$LOG_FILE"
}

# Function to send notification
send_notification() {
	notify-send -t 3000 "Zoom Meeting" "Zoom Meeting Window set to stay on top"
}

# Initialize script
log_message "Monitor started"

# Function to check if Zoom is running
is_zoom_running() {
	# Look for the main Zoom process
	if pgrep -f "^/opt/zoom/zoom" >/dev/null 2>&1; then
		return 0
	else
		return 1
	fi
}

# Function to check if a window is already on top
is_on_top() {
	local window_id=$1
	xprop -id "$window_id" | grep -q "_NET_WM_STATE_ABOVE"
	return $?
}

# Function to put window on top
put_on_top() {
	local window_id=$1
	local window_title=$2

	log_message "Setting meeting window on top"

	# Wait for audio setup
	sleep 3

	# Put window on top
	wmctrl -i -r "$window_id" -b add,above
	send_notification
}

# Track Zoom's running state
zoom_was_running=false

# Main loop
while true; do
	if is_zoom_running; then
		if [ "$zoom_was_running" = false ]; then
			zoom_was_running=true
		fi

		# Get all windows and check for meeting window
		while IFS= read -r line; do
			window_id=$(echo "$line" | awk '{print $1}')
			window_title=$(echo "$line" | cut -d' ' -f4-)

			# Check if it's a Zoom meeting window
			if [ "$window_title" = "pop-os Meeting" ]; then
				if ! is_on_top "$window_id"; then
					put_on_top "$window_id" "$window_title"
				fi
			fi
		done < <(wmctrl -l)
	else
		if [ "$zoom_was_running" = true ]; then
			zoom_was_running=false
		fi
	fi

	sleep 2
done
