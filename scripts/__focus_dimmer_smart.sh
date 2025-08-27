#!/usr/bin/env bash
# Smart focus dimmer - only activates for split-screen layouts
# Dims inactive windows only when windows are arranged side-by-side

set -eo pipefail

# Configuration
DIM_OPACITY="0xd9999999"  # 85% opacity for inactive windows
CHECK_INTERVAL=0.5         # How often to check focus (seconds)

# Get currently focused window
get_focused_window() {
    xdotool getwindowfocus 2>/dev/null || echo ""
}

# Check if windows are in split layout (side-by-side)
is_split_layout() {
    local firefox_windows=()
    local alacritty_windows=()
    local slack_windows=()
    local visible_app_windows=0
    
    # Get all visible application windows with their geometry
    for win_id in $(xdotool search --onlyvisible --name ".*"); do
        window_class=$(xprop -id "$win_id" WM_CLASS 2>/dev/null)
        
        # Check if it's a regular application window
        if echo "$window_class" | grep -qE "firefox|Navigator"; then
            # Get window geometry
            geometry=$(xdotool getwindowgeometry "$win_id" 2>/dev/null | grep "Geometry" | sed 's/.*Geometry: //')
            width=$(echo "$geometry" | cut -d'x' -f1)
            height=$(echo "$geometry" | cut -d'x' -f2)
            
            # Check if window is NOT maximized (typical split is ~half screen width)
            screen_width=$(xdpyinfo 2>/dev/null | awk '/dimensions:/ {print $2}' | cut -d'x' -f1)
            if [ -n "$screen_width" ] && [ -n "$width" ]; then
                # If window width is less than 70% of screen width, it's likely split
                threshold=$((screen_width * 70 / 100))
                if [ "$width" -lt "$threshold" ]; then
                    firefox_windows+=("$win_id")
                    visible_app_windows=$((visible_app_windows + 1))
                fi
            fi
        elif echo "$window_class" | grep -qE "Alacritty"; then
            geometry=$(xdotool getwindowgeometry "$win_id" 2>/dev/null | grep "Geometry" | sed 's/.*Geometry: //')
            width=$(echo "$geometry" | cut -d'x' -f1)
            screen_width=$(xdpyinfo 2>/dev/null | awk '/dimensions:/ {print $2}' | cut -d'x' -f1)
            if [ -n "$screen_width" ] && [ -n "$width" ]; then
                threshold=$((screen_width * 70 / 100))
                if [ "$width" -lt "$threshold" ]; then
                    alacritty_windows+=("$win_id")
                    visible_app_windows=$((visible_app_windows + 1))
                fi
            fi
        elif echo "$window_class" | grep -qE "Slack|slack"; then
            geometry=$(xdotool getwindowgeometry "$win_id" 2>/dev/null | grep "Geometry" | sed 's/.*Geometry: //')
            width=$(echo "$geometry" | cut -d'x' -f1)
            screen_width=$(xdpyinfo 2>/dev/null | awk '/dimensions:/ {print $2}' | cut -d'x' -f1)
            if [ -n "$screen_width" ] && [ -n "$width" ]; then
                threshold=$((screen_width * 70 / 100))
                if [ "$width" -lt "$threshold" ]; then
                    slack_windows+=("$win_id")
                    visible_app_windows=$((visible_app_windows + 1))
                fi
            fi
        fi
    done
    
    # Check for known split layouts:
    # - firefox/firefox
    # - firefox/alacritty
    # - slack/firefox
    # - slack/alacritty
    # Only return true if we have exactly 2 non-maximized windows
    if [ "$visible_app_windows" -eq 2 ]; then
        return 0  # true - split layout detected
    fi
    
    return 1  # false - not a split layout
}

# Get the two split windows
get_split_windows() {
    local windows=()
    for win_id in $(xdotool search --onlyvisible --name ".*"); do
        window_class=$(xprop -id "$win_id" WM_CLASS 2>/dev/null)
        if echo "$window_class" | grep -qE "firefox|Navigator|Alacritty|Slack|slack|Code|code"; then
            geometry=$(xdotool getwindowgeometry "$win_id" 2>/dev/null | grep "Geometry" | sed 's/.*Geometry: //')
            width=$(echo "$geometry" | cut -d'x' -f1)
            screen_width=$(xdpyinfo 2>/dev/null | awk '/dimensions:/ {print $2}' | cut -d'x' -f1)
            if [ -n "$screen_width" ] && [ -n "$width" ]; then
                threshold=$((screen_width * 70 / 100))
                if [ "$width" -lt "$threshold" ]; then
                    windows+=("$win_id")
                fi
            fi
        fi
    done
    echo "${windows[@]}"
}

# Apply dimming based on focus
apply_focus_dimming() {
    local focused_window="$1"
    
    # Only apply dimming if in split layout
    if ! is_split_layout; then
        # Not in split layout - ensure all windows are at full opacity
        for win_id in $(xdotool search --onlyvisible --name ".*"); do
            xprop -id "$win_id" -remove _NET_WM_WINDOW_OPACITY 2>/dev/null
        done
        return
    fi
    
    # Get the two windows in split layout
    local split_windows=($(get_split_windows))
    
    # Minimize all OTHER windows (not in the split pair)
    for win_id in $(xdotool search --onlyvisible --name ".*"); do
        window_class=$(xprop -id "$win_id" WM_CLASS 2>/dev/null)
        
        # Check if it's an app window
        if echo "$window_class" | grep -qE "firefox|Navigator|Alacritty|Slack|slack|Code|code"; then
            # Check if this window is one of the split pair
            local is_split_window=false
            for split_win in "${split_windows[@]}"; do
                if [ "$win_id" = "$split_win" ]; then
                    is_split_window=true
                    break
                fi
            done
            
            if [ "$is_split_window" = true ]; then
                # This is one of the split windows - apply dimming logic
                if [ "$win_id" = "$focused_window" ]; then
                    # Remove opacity from focused window
                    xprop -id "$win_id" -remove _NET_WM_WINDOW_OPACITY 2>/dev/null
                else
                    # Apply dim to unfocused windows
                    xprop -id "$win_id" -f _NET_WM_WINDOW_OPACITY 32c -set _NET_WM_WINDOW_OPACITY "$DIM_OPACITY" 2>/dev/null
                fi
            else
                # This window is not part of the split - minimize it
                xdotool windowminimize "$win_id" 2>/dev/null
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
echo "Starting smart focus dimmer (split layouts only)..."
echo "Press Ctrl+C to stop"

last_focused=""
last_layout_state="single"

while true; do
    current_focused=$(get_focused_window)
    
    # Check if we're in split layout
    if is_split_layout; then
        current_layout_state="split"
        # Only update if focus changed or just entered split layout
        if [ "$current_focused" != "$last_focused" ] || [ "$last_layout_state" != "split" ]; then
            if [ -n "$current_focused" ]; then
                apply_focus_dimming "$current_focused"
                last_focused="$current_focused"
            fi
        fi
    else
        # Not in split layout
        if [ "$last_layout_state" = "split" ]; then
            # Just left split layout - reset all opacity
            for win_id in $(xdotool search --onlyvisible --name ".*"); do
                xprop -id "$win_id" -remove _NET_WM_WINDOW_OPACITY 2>/dev/null
            done
        fi
        current_layout_state="single"
    fi
    
    last_layout_state="$current_layout_state"
    sleep "$CHECK_INTERVAL"
done