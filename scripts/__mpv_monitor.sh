#!/usr/bin/env bash
# PROJECT: mpv-monitor with notifications

LOG_FILE="/home/decoder/mpv_monitor.log"

log_message() {
	echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >>"$LOG_FILE"
}

send_notification() {
	notify-send -t 3000 "MPV Player" "MPV Player Window set to stay on top"
}

is_on_top() {
	xprop -id "$1" | grep -q "_NET_WM_STATE_ABOVE"
}

put_on_top() {
	log_message "Setting MPV window on top: $2"
	sleep 3
	wmctrl -i -r "$1" -b add,above
	send_notification
}

log_message "Monitor started"
declare -A notified_windows

while true; do
	if pgrep -f "mpv" >/dev/null 2>&1; then
		while IFS= read -r line; do
			window_id=$(echo "$line" | awk '{print $1}')
			window_title=$(echo "$line" | cut -d' ' -f4-)

			if echo "$window_title" | grep -qi "mpv\|\.mp4\|\.mkv\|\.avi\|\.mov\|\.webm\|\.flv\|\.m4v"; then
				if ! is_on_top "$window_id"; then
					if [[ -z "${notified_windows[$window_id]}" ]]; then
						put_on_top "$window_id" "$window_title"
						notified_windows[$window_id]=1
					else
						wmctrl -i -r "$window_id" -b add,above
					fi
				fi
			fi
		done < <(wmctrl -l)
	fi
	sleep 2
done