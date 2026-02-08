#!/usr/bin/env bash
set -eo pipefail

# List TOTP accounts, let user pick one, copy code to clipboard
accounts=$(ykman oath accounts list 2>/dev/null || true)
[[ -z "$accounts" ]] && { notify-send "TOTP" "No YubiKey detected"; exit 0; }

selected=$(echo "$accounts" | wofi --dmenu --prompt "TOTP Account" 2>/dev/null) || exit 0
[[ -z "$selected" ]] && exit 0

code=$(ykman oath accounts code -s "$selected" 2>/dev/null)
if [[ -n "$code" ]]; then
	echo -n "$code" | wl-copy
	notify-send "TOTP" "Code for $selected copied to clipboard"
else
	notify-send "TOTP" "Failed to get code for $selected"
fi
