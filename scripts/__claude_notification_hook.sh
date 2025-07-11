#!/usr/bin/env bash
# Claude notification hook - replaces tmux pipe-pane detection
set -eo pipefail

# Read JSON input from stdin
INPUT=$(cat)

# Extract notification data
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
MESSAGE=$(echo "$INPUT" | jq -r '.message // ""')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""')

# Only process if we have a message
if [ -n "$MESSAGE" ]; then
    # Find tmux coordinates from broadcast tracking files
    TMUX_INFO=""
    for broadcast_file in /tmp/claude_broadcast_*.json; do
        if [ -f "$broadcast_file" ]; then
            # Check if file is recent (within last hour)
            if [ -z "$(find "$broadcast_file" -mmin +60 2>/dev/null)" ]; then
                TMUX_SESSION=$(jq -r '.session // ""' "$broadcast_file")
                TMUX_WINDOW=$(jq -r '.window // ""' "$broadcast_file")
                TMUX_PANE=$(jq -r '.pane // ""' "$broadcast_file")
                
                if [ -n "$TMUX_SESSION" ] && [ -n "$TMUX_WINDOW" ] && [ -n "$TMUX_PANE" ]; then
                    TMUX_INFO="${TMUX_SESSION}:${TMUX_WINDOW}:${TMUX_PANE}"
                    break
                fi
            fi
        fi
    done
    
    # Create notification file for Argos/notification system
    TIMESTAMP=$(date +%s)
    
    if [ -n "$TMUX_INFO" ]; then
        IFS=':' read -r TMUX_SESSION TMUX_WINDOW TMUX_PANE <<< "$TMUX_INFO"
        # Sanitize session name for filename (replace / with -)
        SAFE_SESSION_NAME=$(echo "$TMUX_SESSION" | tr '/' '-')
        NOTIFICATION_FILE="/tmp/claude-notification-${SAFE_SESSION_NAME}-${TMUX_WINDOW}-${TMUX_PANE}-${TIMESTAMP}"
        
        # Get pane ID (like %0, %1, etc)
        PANE_ID=$(tmux list-panes -t "${TMUX_SESSION}:${TMUX_WINDOW}" -F '#{pane_index} #{pane_id}' | grep "^$TMUX_PANE " | awk '{print $2}' || echo "%$TMUX_PANE")
        
        # Determine notification type based on message
        if [[ "$MESSAGE" =~ "permission" ]] || [[ "$MESSAGE" =~ "Do you want to" ]]; then
            TITLE="Claude needs input - cycle through sessions"
        elif [[ "$MESSAGE" =~ "ready" ]]; then
            TITLE="Claude is ready - cycle through sessions"
        else
            TITLE="Claude notification"
        fi
        
        # Check if notification already exists to prevent duplicates
        if ! ls /tmp/claude-notification-${SAFE_SESSION_NAME}-${TMUX_WINDOW}-${TMUX_PANE}-* 2>/dev/null | head -1 >/dev/null; then
            # Create notification file content - EXACT format for Argos
            echo "${TMUX_SESSION}:${TMUX_WINDOW}:${PANE_ID}:${TITLE}" > "$NOTIFICATION_FILE"
        fi
    fi
fi

exit 0