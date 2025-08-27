#!/usr/bin/env bash
# Simple focus dimmer - dims inactive windows when multiple windows are visible
# This is the version that actually worked!

set -eo pipefail

# Configuration
# DIM_OPACITY can be set as environment variable (90% = 0xe6666666, 95% = 0xf3333333, 85% = 0xd9999999)
DIM_OPACITY="${DIM_OPACITY:-0xe6666666}"  # Default: 90% opacity for inactive windows
CHECK_INTERVAL="${CHECK_INTERVAL:-0.5}"   # How often to check focus (seconds)

# Get currently focused window
get_focused_window() {
    xdotool getwindowfocus 2>/dev/null || echo ""
}

# Apply dimming based on focus
apply_focus_dimming() {
    local focused_window="$1"
    
    # Apply dimming to all windows based on focus
    for win_id in $(xdotool search --onlyvisible --name ".*"); do
        window_class=$(xprop -id "$win_id" WM_CLASS 2>/dev/null)
        
        # Only affect regular application windows
        if echo "$window_class" | grep -qE "firefox|Navigator|Alacritty|Slack|slack|Code|code|Chrome|chromium"; then
            if [ "$win_id" = "$focused_window" ]; then
                # Remove opacity from focused window
                xprop -id "$win_id" -remove _NET_WM_WINDOW_OPACITY 2>/dev/null
            else
                # Apply dim to unfocused windows
                xprop -id "$win_id" -f _NET_WM_WINDOW_OPACITY 32c -set _NET_WM_WINDOW_OPACITY "$DIM_OPACITY" 2>/dev/null
            fi
        fi
    done
}

# Cleanup on exit
cleanup() {
    echo "Cleaning up - resetting all window opacity..."
    for win_id in $(xdotool search --onlyvisible --name ".*"); do
        xprop -id "$win_id" -remove _NET_WM_WINDOW_OPACITY 2>/dev/null
    done
    exit 0
}

trap cleanup EXIT INT TERM

# Main loop
echo "Starting simple focus dimmer..."
echo "Press Ctrl+C to stop"

last_focused=""
while true; do
    current_focused=$(get_focused_window)
    
    # Only update if focus changed
    if [ "$current_focused" != "$last_focused" ] && [ -n "$current_focused" ]; then
        apply_focus_dimming "$current_focused"
        last_focused="$current_focused"
    fi
    
    sleep "$CHECK_INTERVAL"
done