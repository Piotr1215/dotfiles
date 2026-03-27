#!/usr/bin/env bash

# Source generic error handling function
source __trap.sh

# Set strict error handling
set -eo pipefail

# Function to display help message
help_function() {
	echo "Usage: __boot.sh [-h|--help]"
	echo ""
	echo "This script automates the boot process based on the current day of the week."
	echo "It sets specific bash options for error handling and executes different commands"
	echo "depending on whether it's a weekday or weekend."
	echo ""
	echo "Options:"
	echo "  -h, --help    Show this help message and exit."
	echo ""
	echo "Features:"
	echo "  - Sources a generic error handling function from __trap.sh."
	echo "  - Sets specific bash options for error handling (set -eo pipefail)."
	echo "  - Moves Alacritty window to HDMI 0."
	echo "  - Launches Chrome for work (weekdays) or LibreWolf for home (weekends)."
	echo ""
	echo "Note: This script includes debug options and references to other scripts."
}

# Check for help argument
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
	help_function
	exit 0
fi

weekdays=('Monday' 'Tuesday' 'Wednesday' 'Thursday' 'Friday')

timeoff=1

current_day=$(date +"%A")

echo "$current_day"

# Function to move Alacritty to HDMI 0
move_alacritty_to_hdmi_0() {
	while ! wmctrl -l | grep -q Alacritty; do
		sleep 0.5
	done
	wmctrl -r Alacritty -b remove,maximized_vert,maximized_horz
	wmctrl -r Alacritty -e 0,1920,0,-1,-1
	WID=$(xdotool search --onlyvisible --classname Alacritty | head -1)
	sleep 3
	wmctrl -r Alacritty -b add,maximized_vert,maximized_horz
	xdotool windowactivate --sync "$WID"
	xdotool windowraise "$WID"
}

if [[ " ${weekdays[*]} " =~ $current_day ]] && [[ "$timeoff" == 0 ]]; then
	rm -f /tmp/timeoff_mode
	xdg-settings set default-web-browser google-chrome.desktop 2>/dev/null
	/home/decoder/dev/dotfiles/scripts/__create_recurring_tasks.sh
	flatpak run com.slack.Slack 2>/dev/null &
	nohup google-chrome-stable >/dev/null 2>&1 &
	alacritty &
	move_alacritty_to_hdmi_0
else
	# Weekend :)
	touch /tmp/timeoff_mode
	xdg-settings set default-web-browser io.gitlab.librewolf-community.desktop 2>/dev/null
	nohup flatpak run io.gitlab.librewolf-community >/dev/null 2>&1 &
	alacritty &
	move_alacritty_to_hdmi_0
fi
