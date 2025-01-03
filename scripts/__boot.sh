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
	echo "  - Launches specific Firefox profiles for work or home, depending on the day."
	echo ""
	echo "Note: This script includes debug options and references to other scripts."
}

# Check for help argument
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
	help_function
	exit 0
fi

weekdays=('Monday' 'Tuesday' 'Wednesday' 'Thursday' 'Friday')

timeoff=0

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

# Function to modify profiles.ini
update_profiles_ini() {
	profile_to_set=$1
	profiles_ini_path="$HOME/.mozilla/firefox/profiles.ini"

	# Backup current profiles.ini
	cp "$profiles_ini_path" "$profiles_ini_path.bak"

	# Update the profiles.ini
	awk -v profile="$profile_to_set" '
    /^\[Install/ {
        print
        found=1
        next
    }
    found && /^Default=/ {
        sub(/=.*/, "=" profile)
        print
        next
    }
    {
        print
    }' "$profiles_ini_path" >"$profiles_ini_path.tmp" && mv "$profiles_ini_path.tmp" "$profiles_ini_path"

	echo "Updated profiles.ini to use profile: $profile_to_set"
}

if [[ " ${weekdays[*]} " =~ $current_day ]] && [[ "$timeoff" == 0 ]]; then
	/home/decoder/dev/dotfiles/scripts/__create_recurring_tasks.sh
	update_profiles_ini "8gtkyq7h.Work"
	flatpak run com.slack.Slack 2>/dev/null &
	nohup firefox -P "Work" >/dev/null 2>&1 &
	alacritty &
	move_alacritty_to_hdmi_0
else
	# Weekend :)
	update_profiles_ini "g4ip39zz.default-release"
	nohup firefox -P "Home" >/dev/null 2>&1 &
	alacritty &
	move_alacritty_to_hdmi_0
fi
