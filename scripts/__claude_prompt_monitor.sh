#!/usr/bin/env bash
# PROJECT: ai
# DOCUMENTATION: /home/decoder/dev/obsidian/decoder/Notes/projects/claude-notification.md
set -eo pipefail

# This script is now minimal since notifications are handled by Claude hooks
# It only manages the pane-focus-in hook for auto-clearing notifications

TMUX_SESSION=$(tmux display-message -p '#S')
TMUX_WINDOW=$(tmux display-message -p '#I')
TMUX_WINDOW_NAME=$(tmux display-message -p '#W')
TMUX_PANE=$(tmux display-message -p '#P')
TMUX_PANE_ID=$(tmux display-message -p '#{pane_id}')
# Sanitize session name for filename (replace / with -)
SAFE_SESSION_NAME=$(echo "$TMUX_SESSION" | tr '/' '-')
STATE_FILE="/tmp/claude_monitor_state_${SAFE_SESSION_NAME}_${TMUX_WINDOW}_${TMUX_PANE}"

setup_focus_hook() {
    # Enable focus events if not already enabled
    tmux set-option -t "$TMUX_SESSION" focus-events on
    
    # Set up pane-focus-in hook to auto-clear notifications when manually returning to this pane
    echo "Setting pane-focus-in hook for pane $TMUX_PANE_ID (session: $TMUX_SESSION, window: $TMUX_WINDOW, pane: $TMUX_PANE)" >> "$STATE_FILE"
    tmux set-hook -t "$TMUX_PANE_ID" pane-focus-in \
        "run-shell 'rm -f /tmp/claude-notification-${SAFE_SESSION_NAME}-${TMUX_WINDOW}-${TMUX_PANE}-*'" 2>&1 | tee -a "$STATE_FILE"
    echo "Hook set command completed with exit code: $?" >> "$STATE_FILE"
    
    echo "Focus hook set - notifications will be cleared when returning to this pane" >> "$STATE_FILE"
}

monitor_loop() {
    # Since we're not using pipe-pane anymore, just keep the script running
    # to maintain the focus hook and state file
    echo "Monitor running in hook-only mode (no pipe-pane)" >> "$STATE_FILE"
    echo "Notifications are handled by Claude's Stop and Notification hooks" >> "$STATE_FILE"
    
    # Keep the script running
    while true; do
        sleep 60
        # Periodically check if tmux session still exists
        if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
            echo "Tmux session no longer exists, exiting" >> "$STATE_FILE"
            break
        fi
    done
}

cleanup() {
    # Remove the pane-focus-in hook
    tmux set-hook -u -t "$TMUX_PANE_ID" pane-focus-in 2>/dev/null || true
    
    # Clean up state file
    rm -f "$STATE_FILE"
    exit 0
}

trap cleanup EXIT INT TERM

case "${1:-}" in
    start)
        echo "Starting Claude prompt monitor (hook-only mode) for session: $TMUX_SESSION, window: $TMUX_WINDOW, pane: $TMUX_PANE"
        setup_focus_hook
        monitor_loop
        ;;
    stop)
        /usr/bin/pkill -f "claude_prompt_monitor.*${TMUX_SESSION}_${TMUX_WINDOW}_${TMUX_PANE}" || true
        echo "Stopped Claude prompt monitor"
        ;;
    *)
        echo "Usage: $0 {start|stop}"
        echo ""
        echo "This script sets up tmux hooks for Claude notification management."
        echo "Actual notifications are handled by Claude's Stop and Notification hooks."
        echo ""
        echo "Environment variables used:"
        echo "  TMUX_SESSION: $TMUX_SESSION"
        echo "  TMUX_WINDOW: $TMUX_WINDOW"  
        echo "  TMUX_PANE: $TMUX_PANE"
        echo "  TMUX_PANE_ID: $TMUX_PANE_ID"
        echo ""
        echo "Files created:"
        echo "  State file: $STATE_FILE"
        ;;
esac