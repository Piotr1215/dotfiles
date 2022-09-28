#!/usr/bin/env bash
function remind() {
	local COUNT="$#"
	local COMMAND="$1"
	local MESSAGE="$1"
	local OP="$2"
	shift 2
	local WHEN="$@"
	# Display help if no parameters or help command
	if [[ $COUNT -eq 0 || "$COMMAND" == "help" || "$COMMAND" == "--help" || "$COMMAND" == "-h" ]]; then
		echo "COMMAND"
		echo "    remind <message> <time>"
		echo "    remind <command>"
		echo
		echo "DESCRIPTION"
		echo "    Displays notification at specified time"
		echo
		echo "EXAMPLES"
		echo '    remind "Hi there" now'
		echo '    remind "Time to wake up" in 5 minutes'
		echo '    remind "Dinner" in 1 hour'
		echo '    remind "Take a break" at noon'
		echo '    remind "Are you ready?" at 13:00'
		echo '    remind list'
		echo '    remind clear'
		echo '    remind help'
		echo
		return
	fi
	# Check presence of AT command
	if ! which at >/dev/null; then
		echo "remind: AT utility is required but not installed on your system. Install it with your package manager of choice, for example 'sudo apt install at'."
		return
	fi
	# Run commands: list, clear
	if [[ $COUNT -eq 1 ]]; then
		if [[ "$COMMAND" == "list" ]]; then
			at -l
		elif [[ "$COMMAND" == "clear" ]]; then
			at -r $(atq | cut -f1)
		else
			echo "remind: unknown command $COMMAND. Type 'remind' without any parameters to see syntax."
		fi
		return
	fi
	# Determine time of notification
	if [[ "$OP" == "in" ]]; then
		local TIME="now + $WHEN"
	elif [[ "$OP" == "at" ]]; then
		local TIME="$WHEN"
	elif [[ "$OP" == "now" ]]; then
		local TIME="now"
	else
		echo "remind: invalid time operator $OP"
		return
	fi
	# Schedule the notification
	echo "notify-send '$MESSAGE' 'Reminder' -u critical" | at $TIME 2>/dev/null
	echo "Notification scheduled at $TIME"
}

remind "$@"
