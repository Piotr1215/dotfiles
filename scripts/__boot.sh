#!/usr/bin/env bash

# Source generic error handling funcion
source __trap.sh

# The set -e option instructs bash to immediately exit if any command has a non-zero exit status
# The set -u referencing a previously undefined  variable - with the exceptions of $* and $@ - is an error
# The set -o pipefaile if any command in a pipeline fails, that return code will be used as the return code of the whole pipeline
# https://bit.ly/37nFgin
set -eo pipefail

# Add source and line number wher running in debug mode: __run_with_xtrace.sh __boot.sh

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

# TODO: boot script switch off timeoff
timeoff=1

current_day=$(date +"%A")

echo "$current_day"

move_alacritty_to_hdmi_0() {
	while [ -z "$(wmctrl -l | grep Alacritty)" ]; do
		sleep 0.5
	done
	wmctrl -r Alacritty -e 0,1920,0,-1,-1
	WID=$(xdotool search --onlyvisible --classname Alacritty | head -1)
	sleep 3
	xdotool windowactivate --sync $WID
	xdotool windowraise $WID
}

if [[ " ${weekdays[*]} " =~ " $current_day " ]] && [[ "$timeoff" == 0 ]]; then
	# flatpak run com.slack.Slack 2>/dev/null &
	nohup firefox -P "Work" about:profiles >/dev/null 2>&1 &
	alacritty &
	move_alacritty_to_hdmi_0
else
	#Weekend :)
	nohup firefox -P "Home" about:profiles >/dev/null 2>&1 &
	alacritty &
	move_alacritty_to_hdmi_0
fi
