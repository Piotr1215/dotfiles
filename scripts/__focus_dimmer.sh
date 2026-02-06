#!/usr/bin/env bash
# Robust focus dimmer - dims inactive windows when multiple windows are visible

# Configuration
DIM_OPACITY="${DIM_OPACITY:-0xe6333333}"  # Default: 90% opacity for inactive windows
CHECK_INTERVAL="${CHECK_INTERVAL:-0.5}"   # How often to check focus (seconds)
MAX_RETRIES="${MAX_RETRIES:-3}"          # Max retries for window operations
ERROR_COUNT=0                             # Track consecutive errors
MAX_ERRORS="${MAX_ERRORS:-10}"            # Max errors before restart

# Track windows we're managing
declare -A managed_windows

# Verify window still exists
window_exists() {
    local win_id="$1"
    xprop -id "$win_id" WM_CLASS &>/dev/null
}

# Safe window operation with retry
safe_window_op() {
    local win_id="$1"
    local operation="$2"
    local retries=0
    
    # First check if window still exists
    if ! window_exists "$win_id"; then
        unset managed_windows["$win_id"]
        return 1
    fi
    
    while [ $retries -lt $MAX_RETRIES ]; do
        if eval "$operation" 2>/dev/null; then
            return 0
        fi
        ((retries++))
        sleep 0.05
    done
    
    # Window operation failed, likely window was destroyed
    unset managed_windows["$win_id"]
    return 1
}

# Get currently focused window
get_focused_window() {
    xdotool getwindowfocus 2>/dev/null || echo ""
}

# Apply dimming based on focus
apply_focus_dimming() {
    local focused_window="$1"
    local errors_this_run=0
    
    # Get visible windows
    local visible_windows
    if ! visible_windows=$(xdotool search --onlyvisible --name ".*" 2>/dev/null); then
        return 1
    fi
    
    # Process each window
    for win_id in $visible_windows; do
        # Skip if window doesn't exist anymore
        if ! window_exists "$win_id"; then
            continue
        fi
        
        # Get window class safely
        local window_class
        if ! window_class=$(xprop -id "$win_id" WM_CLASS 2>/dev/null); then
            continue
        fi
        
        # Only affect regular application windows (-i for case-insensitive)
        if echo "$window_class" | grep -qiE "firefox|Navigator|Alacritty|Slack|Code|Chrome|Obsidian|Discord|Spotify|Thunderbird"; then
            managed_windows["$win_id"]=1
            
            if [ "$win_id" = "$focused_window" ]; then
                # Remove opacity from focused window
                safe_window_op "$win_id" "xprop -id '$win_id' -remove _NET_WM_WINDOW_OPACITY" || ((errors_this_run++))
            else
                # Apply dim to unfocused windows
                safe_window_op "$win_id" "xprop -id '$win_id' -f _NET_WM_WINDOW_OPACITY 32c -set _NET_WM_WINDOW_OPACITY '$DIM_OPACITY'" || ((errors_this_run++))
            fi
        fi
    done
    
    # Clean up managed_windows of non-existent windows
    for win_id in "${!managed_windows[@]}"; do
        if ! window_exists "$win_id"; then
            unset managed_windows["$win_id"]
        fi
    done
    
    return $errors_this_run
}

# Cleanup on exit
cleanup() {
    echo "Cleaning up - resetting all window opacity..."
    
    # Reset opacity for all managed windows
    for win_id in "${!managed_windows[@]}"; do
        if window_exists "$win_id"; then
            xprop -id "$win_id" -remove _NET_WM_WINDOW_OPACITY 2>/dev/null || true
        fi
    done
    
    # Also try to reset any visible windows we might have missed
    for win_id in $(xdotool search --onlyvisible --name ".*" 2>/dev/null || true); do
        if window_exists "$win_id"; then
            xprop -id "$win_id" -remove _NET_WM_WINDOW_OPACITY 2>/dev/null || true
        fi
    done
    
    exit 0
}

# Handle errors gracefully
handle_error() {
    ((ERROR_COUNT++))
    
    if [ $ERROR_COUNT -ge $MAX_ERRORS ]; then
        echo "Too many consecutive errors ($ERROR_COUNT), exiting gracefully..."
        cleanup
    fi
}

trap cleanup EXIT INT TERM

# Main loop
echo "Starting robust focus dimmer..."
echo "Press Ctrl+C to stop"

last_focused=""
while true; do
    # Get current focused window
    current_focused=$(get_focused_window)
    
    # Only update if focus changed and we have a valid window
    if [ "$current_focused" != "$last_focused" ] && [ -n "$current_focused" ]; then
        if apply_focus_dimming "$current_focused"; then
            # Reset error count on successful operation
            ERROR_COUNT=0
            last_focused="$current_focused"
        else
            handle_error
        fi
    elif [ -z "$current_focused" ]; then
        # No focused window, might be switching workspaces
        ERROR_COUNT=0
    fi
    
    sleep "$CHECK_INTERVAL"
done