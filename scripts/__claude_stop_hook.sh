#!/usr/bin/env bash
# Claude Stop event hook - detects when Claude finishes processing and creates notifications
set -eo pipefail

LOG_FILE="/tmp/claude-stop-hook.log"

# Read JSON input from stdin
INPUT=$(cat)

# Extract session ID and other relevant data
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
DURATION=$(echo "$INPUT" | jq -r '.duration // ""')

echo "[$(date)] Stop hook triggered - Claude finished processing (duration: ${DURATION}ms)" >> "$LOG_FILE"

# Find the broadcast file for this session to get tmux coordinates
find_tmux_info() {
    local session_id="$1"
    
    for broadcast_file in /tmp/claude_broadcast_*.json; do
        if [ -f "$broadcast_file" ]; then
            local file_session_id
            file_session_id=$(jq -r '.session_id // ""' "$broadcast_file" 2>/dev/null)
            if [ "$file_session_id" = "$session_id" ]; then
                local tmux_session tmux_window tmux_pane
                tmux_session=$(jq -r '.session // ""' "$broadcast_file" 2>/dev/null)
                tmux_window=$(jq -r '.window // ""' "$broadcast_file" 2>/dev/null)
                tmux_pane=$(jq -r '.pane // ""' "$broadcast_file" 2>/dev/null)
                
                if [ -n "$tmux_session" ] && [ -n "$tmux_window" ] && [ -n "$tmux_pane" ]; then
                    echo "${tmux_session}:${tmux_window}:${tmux_pane}"
                    return 0
                fi
            fi
        fi
    done
    
    return 1
}

# Create notification when Claude finishes processing
create_notification() {
    local tmux_info="$1"
    
    if [ -z "$tmux_info" ]; then
        echo "[$(date)] No tmux info found, skipping notification" >> "$LOG_FILE"
        return
    fi
    
    # Parse tmux coordinates
    IFS=':' read -r TMUX_SESSION TMUX_WINDOW TMUX_PANE <<< "$tmux_info"
    # Sanitize session name for filename (replace / with -)
    SAFE_SESSION_NAME=$(echo "$TMUX_SESSION" | tr '/' '-')
    
    # Check if user is currently in this tmux session/window
    local current_session current_window
    current_session=$(tmux display-message -p '#S' 2>/dev/null || echo "")
    current_window=$(tmux display-message -p '#I' 2>/dev/null || echo "")
    
    local is_inactive=false
    # Check if we're in a different tmux session/window
    if [ "$current_session" != "$TMUX_SESSION" ] || [ "$current_window" != "$TMUX_WINDOW" ]; then
        is_inactive=true
    else
        # Even if we're in the same tmux window, check if terminal has focus
        if command -v xdotool >/dev/null 2>&1 && command -v xprop >/dev/null 2>&1; then
            local active_window_class
            active_window_class=$(xprop -id "$(xdotool getactivewindow 2>/dev/null)" WM_CLASS 2>/dev/null | grep -oP '"\K[^"]+' | tail -1)
            # Check if the active window is NOT a terminal
            if [ -n "$active_window_class" ] && ! [[ "$active_window_class" =~ ^(Alacritty|gnome-terminal|Terminal|xterm|konsole|terminator|kitty|st|urxvt|rxvt)$ ]]; then
                is_inactive=true
            fi
        fi
    fi
    
    # Only create notification if session is inactive
    if [ "$is_inactive" = true ]; then
        local timestamp
        timestamp=$(date +%s)
        local notification_file="/tmp/claude-notification-${SAFE_SESSION_NAME}-${TMUX_WINDOW}-${TMUX_PANE}-${timestamp}"
        
        # Get pane ID (like %0, %1, etc)
        local pane_id
        pane_id=$(tmux list-panes -t "${TMUX_SESSION}:${TMUX_WINDOW}" -F '#{pane_index} #{pane_id}' 2>/dev/null | grep "^$TMUX_PANE " | awk '{print $2}' || echo "%$TMUX_PANE")
        
        local title="Claude is ready - cycle through sessions"
        
        # Check if notification already exists to prevent duplicates
        if ! ls "/tmp/claude-notification-${SAFE_SESSION_NAME}-${TMUX_WINDOW}-${TMUX_PANE}-"* 2>/dev/null | head -1 >/dev/null; then
            # Create notification file content - EXACT format for Argos
            echo "${TMUX_SESSION}:${TMUX_WINDOW}:${pane_id}:${title}" > "$notification_file"
            echo "[$(date)] Created notification: $notification_file" >> "$LOG_FILE"
        else
            echo "[$(date)] Notification already exists, skipping duplicate" >> "$LOG_FILE"
        fi
    else
        echo "[$(date)] Session is active, no notification needed" >> "$LOG_FILE"
    fi
}

# Main logic
if [ -n "$SESSION_ID" ]; then
    # Find tmux info for this session
    TMUX_INFO=$(find_tmux_info "$SESSION_ID" || echo "")
    
    if [ -n "$TMUX_INFO" ]; then
        echo "[$(date)] Found tmux info: $TMUX_INFO" >> "$LOG_FILE"
        
        # Create notification for Claude output ready
        create_notification "$TMUX_INFO"
    else
        echo "[$(date)] No broadcast file found for session: $SESSION_ID" >> "$LOG_FILE"
    fi
else
    echo "[$(date)] Warning: No session ID provided" >> "$LOG_FILE"
fi

exit 0