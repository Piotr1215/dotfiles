#!/usr/bin/env bash
# PROJECT: ai
# DOCUMENTATION: /home/decoder/dev/obsidian/decoder/Notes/projects/claude-notification.md
set -eo pipefail

TMUX_SESSION=$(tmux display-message -p '#S')
TMUX_WINDOW=$(tmux display-message -p '#I')
TMUX_WINDOW_NAME=$(tmux display-message -p '#W')
TMUX_PANE=$(tmux display-message -p '#P')
TMUX_PANE_ID=$(tmux display-message -p '#{pane_id}')
TMUX_PANE_TITLE=$(tmux display-message -p '#{pane_title}')
MONITOR_FILE="/tmp/claude_monitor_${TMUX_SESSION}_${TMUX_WINDOW}_${TMUX_PANE}.txt"
STATE_FILE="/tmp/claude_monitor_state_${TMUX_SESSION}_${TMUX_WINDOW}_${TMUX_PANE}"

notify_prompt() {
    local session="$1"
    local window="$2"
    local window_name="$3"
    local pane="$4"
    local pane_id="$5"
    local pane_title="$6"
    local notification_type="${7:-input}"
    local timestamp=$(date '+%H:%M:%S')
    
    local title
    if [ "$notification_type" = "ready" ]; then
        title="Claude is ready - cycle through sessions"
    else
        title="Claude needs input - cycle through sessions"
    fi
    
    local body="Window: $window_name (#$window)"
    
    if [ -n "$pane_title" ] && [ "$pane_title" != "zsh" ] && [ "$pane_title" != "bash" ]; then
        body="$body\nPane: $pane_title (#$pane)"
    else
        body="$body\nPane: #$pane"
    fi
    
    body="$body\nTime: $timestamp"
    
    # Create notification file for this session/window/pane
    local timestamp=$(date +%s)
    local notification_file="/tmp/claude-notification-${session}-${window}-${pane}-${timestamp}"
    
    # Check if a notification file already exists for this session/window/pane combo to prevent duplicates
    if ! ls /tmp/claude-notification-${session}-${window}-${pane}-* 2>/dev/null | head -1 >/dev/null; then
        # Create notification file with session info
        echo "${session}:${window}:${pane_id}:${title}" > "$notification_file"
    fi
}

monitor_pane() {
    local looking_for_prompt=false
    local last_notification_time=0
    
    # Enable focus events if not already enabled
    tmux set-option -t "$TMUX_SESSION" focus-events on
    
    # Set up pane-focus-in hook to auto-clear notifications when manually returning to this pane
    tmux set-hook -t "$TMUX_PANE_ID" pane-focus-in \
        "run-shell 'rm -f /tmp/claude-notification-${TMUX_SESSION}-${TMUX_WINDOW}-${TMUX_PANE}-*'"
    
    tmux pipe-pane -o -t "$TMUX_PANE_ID" "cat >> $MONITOR_FILE"
    
    tail -f "$MONITOR_FILE" 2>/dev/null | while IFS= read -r line; do
        local current_session=$(tmux display-message -p '#S')
        local current_window=$(tmux display-message -p '#I')
        
        local is_inactive=false
        # Check if we're in a different tmux session/window
        if [ "$current_session" != "$TMUX_SESSION" ] || [ "$current_window" != "$TMUX_WINDOW" ]; then
            is_inactive=true
        else
            # Even if we're in the same tmux window, check if terminal has focus
            if command -v xdotool >/dev/null 2>&1 && command -v xprop >/dev/null 2>&1; then
                local active_window_class=$(xprop -id $(xdotool getactivewindow 2>/dev/null) WM_CLASS 2>/dev/null | grep -oP '"\K[^"]+' | tail -1)
                # Check if the active window is NOT a terminal (Alacritty, gnome-terminal, xterm, etc.)
                if [ -n "$active_window_class" ] && ! [[ "$active_window_class" =~ ^(Alacritty|gnome-terminal|Terminal|xterm|konsole|terminator|kitty|st|urxvt|rxvt)$ ]]; then
                    is_inactive=true
                fi
            fi
        fi
        
        if command -v ansi2txt >/dev/null 2>&1; then
            clean_line=$(echo "$line" | ansi2txt)
        else
            clean_line=$(echo "$line" | sed 's/\x1b\[[0-9;]*m//g' | sed 's/\x1b\[[0-9;]*[A-Za-z]//g')
        fi
        
        if [[ "$clean_line" =~ ^●[[:space:]] ]]; then
            echo "Claude started outputting (found '● ' pattern)" >> "$STATE_FILE"
            
            echo "" > "$MONITOR_FILE"
            
            if [ "$is_inactive" = true ]; then
                notify_prompt "$TMUX_SESSION" "$TMUX_WINDOW" "$TMUX_WINDOW_NAME" "$TMUX_PANE" "$TMUX_PANE_ID" "$TMUX_PANE_TITLE" "ready"
                echo "Claude output detected and notification file created (session/terminal inactive)" >> "$STATE_FILE"
            else
                echo "Claude output detected but session is active, skipping notification" >> "$STATE_FILE"
            fi
        fi
        
        if [[ "$clean_line" =~ "Do you want to" ]]; then
            looking_for_prompt=true
            echo "Found 'Do you want to' pattern" > "$STATE_FILE"
        elif [ "$looking_for_prompt" = true ] && [[ "$clean_line" =~ "❯" ]]; then
            echo "Found prompt indicator ❯" >> "$STATE_FILE"
            
            echo "" > "$MONITOR_FILE"
            
            if [ "$is_inactive" = true ]; then
                notify_prompt "$TMUX_SESSION" "$TMUX_WINDOW" "$TMUX_WINDOW_NAME" "$TMUX_PANE" "$TMUX_PANE_ID" "$TMUX_PANE_TITLE" "input"
                echo "Prompt detected and notification file created (session/terminal inactive)" >> "$STATE_FILE"
            else
                echo "Prompt detected but session is active, skipping notification" >> "$STATE_FILE"
            fi
            
            looking_for_prompt=false
        fi
    done
}

cleanup() {
    # Remove the pane-focus-in hook
    tmux set-hook -u -t "$TMUX_PANE_ID" pane-focus-in 2>/dev/null || true
    
    tmux pipe-pane -t "$TMUX_PANE_ID"
    rm -f "$MONITOR_FILE" "$STATE_FILE"
    exit 0
}

cleanup_old_files() {
    find /tmp -name "claude_monitor_*${TMUX_SESSION}_${TMUX_WINDOW}_${TMUX_PANE}*" -type f -mmin +60 -delete 2>/dev/null || true
}

trap cleanup EXIT INT TERM

case "${1:-}" in
    start)
        echo "Starting Claude prompt monitor for session: $TMUX_SESSION, window: $TMUX_WINDOW, pane: $TMUX_PANE"
        cleanup_old_files
        monitor_pane
        ;;
    stop)
        /usr/bin/pkill -f "claude_prompt_monitor.*${TMUX_SESSION}_${TMUX_WINDOW}_${TMUX_PANE}" || true
        cleanup_old_files
        echo "Stopped Claude prompt monitor"
        ;;
    *)
        echo "Usage: $0 {start|stop}"
        echo ""
        echo "This script monitors tmux pane output for Claude interactive prompts"
        echo "and sends desktop notifications when the session is not active."
        echo ""
        echo "Environment variables used:"
        echo "  TMUX_SESSION: $TMUX_SESSION"
        echo "  TMUX_WINDOW: $TMUX_WINDOW"  
        echo "  TMUX_PANE: $TMUX_PANE"
        echo "  TMUX_PANE_ID: $TMUX_PANE_ID"
        echo ""
        echo "Files created:"
        echo "  Monitor file: $MONITOR_FILE"
        echo "  State file: $STATE_FILE"
        ;;
esac