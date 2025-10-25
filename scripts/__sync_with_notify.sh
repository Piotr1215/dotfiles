#!/usr/bin/env bash

# Log file for debugging
LOG_FILE="/tmp/github-issue-sync.log"

# Set up environment for the sync script
if [[ -f "$HOME/.envrc" ]]; then
    # shellcheck disable=SC1091
    source "$HOME/.envrc"
else
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: ERROR - ~/.envrc not found" >> "$LOG_FILE"
    notify-send -u critical "✗ Sync failed" "$HOME/.envrc not found"
    exit 1
fi

# Validate required environment variables
if [[ -z "$LINEAR_API_KEY" ]] || [[ -z "$LINEAR_USER_ID" ]]; then
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: ERROR - Required environment variables not set" >> "$LOG_FILE"
    notify-send -u critical "✗ Sync failed" "LINEAR_API_KEY or LINEAR_USER_ID not set"
    exit 1
fi

# Set display variables for notifications
export DISPLAY=:1
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus

# Run the sync script and log output
if ! /home/decoder/dev/dotfiles/scripts/__github_issue_sync.sh >> "$LOG_FILE" 2>&1; then
    # Get last 10 lines of error
    error_msg=$(tail -n 10 "$LOG_FILE" | grep -i "error" | head -n 1 || echo "Check $LOG_FILE")
    notify-send -u critical "✗ Sync failed" "$error_msg"
    exit 1
fi

# Success - keep log clean (last 1000 lines only)
tail -n 1000 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE" 2>/dev/null || true
