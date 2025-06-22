#!/usr/bin/env bash
# Go to the next Claude session using file-based notifications
set -eo pipefail

# Find all Claude notification files
notification_files=(/tmp/claude-notification-*)

# Check if any notification files exist
if [ ! -e "${notification_files[0]}" ]; then
    # No notifications - silently exit
    exit 0
fi

# Find the oldest notification file (by timestamp in filename)
oldest_file=""
oldest_timestamp=999999999999

for file in "${notification_files[@]}"; do
    if [ -f "$file" ]; then
        # Extract timestamp from filename: claude-notification-session-window-pane-TIMESTAMP
        timestamp=$(basename "$file" | sed 's/.*-\([0-9]*\)$/\1/')
        if [ "$timestamp" -lt "$oldest_timestamp" ]; then
            oldest_timestamp="$timestamp"
            oldest_file="$file"
        fi
    fi
done

# If no valid file found, exit
if [ -z "$oldest_file" ] || [ ! -f "$oldest_file" ]; then
    exit 0
fi

# Read session info from the file
session_info=$(cat "$oldest_file")
IFS=':' read -r session window pane_id title <<< "$session_info"

# Remove the notification file since we're handling it
rm -f "$oldest_file"

# First, focus the terminal window (Alacritty)
if command -v wmctrl >/dev/null 2>&1; then
    # Try to activate Alacritty window
    wmctrl -x -a "Alacritty.Alacritty" 2>/dev/null || true
elif command -v xdotool >/dev/null 2>&1; then
    # Alternative: use xdotool to find and activate Alacritty
    xdotool search --class "Alacritty" windowactivate 2>/dev/null || true
fi

# Small delay to ensure window activation completes
sleep 0.1

# Switch to the Claude session
if tmux has-session -t "$session" 2>/dev/null; then
    tmux switch-client -t "$session:$window"
    tmux select-pane -t "$pane_id"
else
    # Session no longer exists, try the next one in files if any remain
    if [ -n "$(ls /tmp/claude-notification-* 2>/dev/null)" ]; then
        exec "$0"  # Recursively call self to process next notification
    fi
fi