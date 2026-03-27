#!/usr/bin/env bash

# Source generic error handling function
source "$(dirname "$0")/__trap.sh"

# Set strict error handling
set -eo pipefail

# Function to display help message
help_function() {
	echo "Usage: __pto.sh [-h|--help]"
	echo ""
	echo "Toggle PTO (Paid Time Off) mode in __boot.sh."
	echo "When PTO mode is enabled, the boot script will use weekend mode"
	echo "even on weekdays (no Slack, no Work profile)."
	echo ""
	echo "Options:"
	echo "  -h, --help    Show this help message and exit."
	echo ""
	echo "Examples:"
	echo "  __pto.sh      Toggle PTO mode on/off"
}

# Check for help argument
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
	help_function
	exit 0
fi

# Get the directory where this script is located
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
boot_script="$script_dir/__boot.sh"

# Check if __boot.sh exists
if [[ ! -f "$boot_script" ]]; then
	echo "Error: __boot.sh not found at $boot_script" >&2
	exit 1
fi

# Read current timeoff value
current_value=$(grep -E "^timeoff=" "$boot_script" | cut -d= -f2)

if [[ -z "$current_value" ]]; then
	echo "Error: Could not find timeoff setting in __boot.sh" >&2
	exit 1
fi

# Toggle the value
if [[ "$current_value" == "0" ]]; then
	new_value=1
	mode="ON"
	emoji="🏖️"
	message="PTO mode enabled! Enjoy your time off!"
else
	new_value=0
	mode="OFF"
	emoji="💼"
	message="PTO mode disabled. Back to work mode!"
fi

# Update the file
sed -i "s/^timeoff=.*/timeoff=$new_value/" "$boot_script"

# Verify the change
updated_value=$(grep -E "^timeoff=" "$boot_script" | cut -d= -f2)

if [[ "$updated_value" != "$new_value" ]]; then
	echo "Error: Failed to update timeoff setting" >&2
	exit 1
fi

# Apply runtime environment switch (mirrors ufp function)
profiles_ini="$HOME/.var/app/io.gitlab.librewolf-community/.librewolf/profiles.ini"

if [[ "$new_value" == "1" ]]; then
	touch /tmp/timeoff_mode
	xdg-settings set default-web-browser io.gitlab.librewolf-community.desktop 2>/dev/null
	if [[ -f "$profiles_ini" ]]; then
		sed -i.bak '/^\[InstallAA67A15BF0F93AE3\]/,/^$/{s|^Default=.*|Default=7fs4462i.decoder|}' "$profiles_ini"
	fi
else
	rm -f /tmp/timeoff_mode
	xdg-settings set default-web-browser google-chrome.desktop 2>/dev/null
	if [[ -f "$profiles_ini" ]]; then
		sed -i.bak '/^\[InstallAA67A15BF0F93AE3\]/,/^$/{s|^Default=.*|Default=j549qbym.Work|}' "$profiles_ini"
	fi
fi

# Refresh tmux status bar
__tmux_active_task.sh --update 2>/dev/null || true
tmux refresh-client -S 2>/dev/null || true

echo ""
echo "  $emoji  $message"
echo ""
echo "  PTO mode is now: $mode"
echo "  (Current setting: timeoff=$new_value)"
echo ""
