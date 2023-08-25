#!/bin/bash

# Help function
display_help() {
	echo "Supported date and time modifiers:"
	echo "  m: minutes"
	echo "  h: hours"
	echo "  d: days"
	echo "  w: weeks"
	echo "  y: years"
	echo "  --: escape hatch for arbitrary 'at' modifiers (e.g., 'Monday eod', '13:00 ETSC')"
	echo "Common 'at' modifiers:"
	echo "  tomorrow, eow (end of week), eod (end of day)"
}

# List reminders
if [[ "$1" == "-l" || "$1" == "--list" ]]; then
	at -l
	exit 0
fi

# Display help
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
	display_help
	exit 0
fi

# Ensure we have access to the X server
xhost +

message="$1"
time_string="$2"

# Define delay based on the given time string
case $time_string in
"--")
	delay="$3" # Accept arbitrary 'at' modifiers
	;;
"tomorrow")
	delay="8:00 AM tomorrow"
	;;
"eow")
	delay="12:00 PM next Fri"
	;;
"eod")
	delay="8:00 PM"
	;;
*m)
	delay="now + ${time_string%m} minutes"
	;;
*h)
	delay="now + ${time_string%h} hours"
	;;
*d)
	delay="now + ${time_string%d} days"
	;;
*w)
	delay="now + ${time_string%w} weeks"
	;;
*y)
	delay="now + ${time_string%y} years"
	;;
*)
	echo "Invalid time format"
	exit 1
	;;
esac

if [[ "$3" != "internal" ]]; then
	echo "$0 '$message' '$time_string' internal" | at $delay
else
	# This part is executed when scheduled by 'at'
	while true; do
		zenity --question --text="$message" --display=":1" \
			--ok-label="Acknowledged" --cancel-label="Remind me in 5 minutes" \
			--width=200 --height=100

		# Check the exit status of zenity
		case $? in
		0) # User clicked "Acknowledged"
			task log "$message" +reminder
			break
			;;
		1)         # User clicked "Remind me in 5 minutes"
			sleep 300 # Sleep for 5 minutes (300 seconds)
			;;
		*) # Any other exit code means an error or unexpected closure
			break
			;;
		esac
	done
fi
