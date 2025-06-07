#!/usr/bin/env bash
set -eo pipefail

# PROJECT: ai
# Claude prompt monitor - watches tmux pane output for interactive prompts

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
    local timestamp=$(date '+%H:%M:%S')
    
    local title="Claude needs input in $session"
    local body="Window: $window_name (#$window)"
    
    # Add pane title if it's meaningful
    if [ -n "$pane_title" ] && [ "$pane_title" != "zsh" ] && [ "$pane_title" != "bash" ]; then
        body="$body\nPane: $pane_title (#$pane)"
    else
        body="$body\nPane: #$pane"
    fi
    
    body="$body\nTime: $timestamp"
    
    response=$(dunstify \
        --timeout 60000 \
        --urgency=critical \
        --action="default,Switch to session" \
        --icon=applications-chat \
        --replace=99999 \
        "$title" \
        "$body")
    
    if [ "$response" = "default" ]; then
        tmux switch-client -t "$session:$window"
        tmux select-pane -t "$pane_id"
    fi
}

monitor_pane() {
    local looking_for_prompt=false
    
    tmux pipe-pane -o -t "$TMUX_PANE_ID" "cat >> $MONITOR_FILE"
    
    tail -f "$MONITOR_FILE" 2>/dev/null | while IFS= read -r line; do
        # Remove ANSI escape codes for easier pattern matching
        clean_line=$(echo "$line" | sed 's/\x1b\[[0-9;]*m//g' | sed 's/\x1b\[[0-9;]*[A-Za-z]//g')
        
        if [[ "$clean_line" =~ "Do you want to" ]]; then
            looking_for_prompt=true
            echo "Found 'Do you want to' pattern" > "$STATE_FILE"
        elif [ "$looking_for_prompt" = true ] && [[ "$clean_line" =~ "❯" ]]; then
            echo "Found prompt indicator ❯" >> "$STATE_FILE"
            
            echo "" > "$MONITOR_FILE"
            
            notify_prompt "$TMUX_SESSION" "$TMUX_WINDOW" "$TMUX_WINDOW_NAME" "$TMUX_PANE" "$TMUX_PANE_ID" "$TMUX_PANE_TITLE"
            
            looking_for_prompt=false
            echo "Prompt detected and notification sent" >> "$STATE_FILE"
        fi
    done
}

cleanup() {
    tmux pipe-pane -t "$TMUX_PANE_ID"
    
    rm -f "$MONITOR_FILE" "$STATE_FILE"
    
    exit 0
}

trap cleanup EXIT INT TERM

case "${1:-}" in
    start)
        echo "Starting Claude prompt monitor for session: $TMUX_SESSION, window: $TMUX_WINDOW, pane: $TMUX_PANE"
        monitor_pane
        ;;
    stop)
        /usr/bin/pkill -f "claude_prompt_monitor.*${TMUX_SESSION}_${TMUX_WINDOW}_${TMUX_PANE}" || true
        echo "Stopped Claude prompt monitor"
        ;;
    *)
        echo "Usage: $0 {start|stop}"
        echo ""
        echo "This script monitors tmux pane output for Claude interactive prompts"
        echo "and sends notifications when input is needed."
        echo ""
        echo "Example:"
        echo "  $0 start  # Start monitoring current pane"
        echo "  $0 stop   # Stop monitoring"
        exit 1
        ;;
esac
