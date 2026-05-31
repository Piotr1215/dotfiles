#!/usr/bin/env bash
set -eo pipefail

# Argos click handler: generate the TOTP code for the given account and copy it
# to the clipboard. Invoked from totp.30s.sh with the account name as $1.

account="$1"
[ -z "$account" ] && { notify-send "TOTP" "No account passed"; exit 1; }

# Extract only a real 6-8 digit OTP; ignores touch prompts / error text.
# Touch-required (-t) accounts block here until the YubiKey is tapped.
code=$(ykman oath accounts code -s "$account" 2>/dev/null | grep -oE '[0-9]{6,8}' | tail -1)

if [ -z "$code" ]; then
    notify-send "TOTP" "Failed to get code for $account"
    exit 1
fi

# Prefer Wayland clipboard if running under it, else X11.
if [ -n "$WAYLAND_DISPLAY" ] && command -v wl-copy >/dev/null 2>&1; then
    printf '%s' "$code" | wl-copy
else
    printf '%s' "$code" | xclip -selection clipboard
fi

notify-send "TOTP" "Code for $account copied"
