#!/usr/bin/env bash

# Set up environment for the sync script
source ~/.envrc

# Set display variables for notifications
export DISPLAY=:1
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus

# Run the sync script
if /home/decoder/dev/dotfiles/scripts/__github_issue_sync.sh >/dev/null 2>&1; then
    notify-send "✓ Tasks synced" "Linear & GitHub issues synchronized"
else
    notify-send -u critical "✗ Sync failed" "Check the sync script"
fi