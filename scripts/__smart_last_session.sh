#!/usr/bin/env bash

# Configuration
HISTORY_FILE="$HOME/.tmux_session_history"
MAX_HISTORY_ENTRIES=20

# Get current session name
CURRENT_SESSION=$(tmux display-message -p '#S')

# Function to clean up history file
function cleanup_history() {
    if [[ -f "$HISTORY_FILE" ]]; then
        # Remove killed sessions and keep only recent entries
        local temp_file="${HISTORY_FILE}.tmp"
        : > "$temp_file"
        
        tail -n "$MAX_HISTORY_ENTRIES" "$HISTORY_FILE" | while read -r line; do
            local session_name
            session_name=$(echo "$line" | cut -d' ' -f2-)
            if [[ -n "$session_name" ]] && tmux has-session -t "$session_name" 2>/dev/null; then
                echo "$line" >> "$temp_file"
            fi
        done
        
        mv "$temp_file" "$HISTORY_FILE"
    fi
}

# Function to add session to history
function add_to_history() {
    local session="$1"
    # Don't add git-monitor sessions to history
    if [[ "$session" != git-monitor-* ]]; then
        # Check if the last entry is the same session to avoid duplicates
        if [[ -f "$HISTORY_FILE" ]]; then
            local last_session
            last_session=$(tail -1 "$HISTORY_FILE" 2>/dev/null | cut -d' ' -f2- || true)
            if [[ "$last_session" == "$session" ]]; then
                return 0
            fi
        fi
        echo "$(date +%s) $session" >> "$HISTORY_FILE"
        cleanup_history
    fi
}

# Function to get last non-git-monitor session from history
function get_last_valid_session() {
    if [[ ! -f "$HISTORY_FILE" ]]; then
        return 1
    fi
    
    # Get unique sessions in reverse order (most recent first)
    local seen_sessions=""
    tac "$HISTORY_FILE" | while read -r line; do
        local session_name
        session_name=$(echo "$line" | cut -d' ' -f2-)
        
        # Skip if empty, git-monitor, or current session
        if [[ -z "$session_name" ]] || \
           [[ "$session_name" == git-monitor-* ]] || \
           [[ "$session_name" == "$CURRENT_SESSION" ]]; then
            continue
        fi
        
        # Skip if we've already seen this session
        if [[ "$seen_sessions" == *"$session_name"* ]]; then
            continue
        fi
        seen_sessions="$seen_sessions $session_name"
        
        # Check if session still exists
        if tmux has-session -t "$session_name" 2>/dev/null; then
            echo "$session_name"
            return 0
        fi
    done
    
    return 1
}

# Main logic
if [[ "$CURRENT_SESSION" == git-monitor-* ]]; then
    # We're in a git-monitor session, try to return to last non-git-monitor session
    TARGET_SESSION=$(get_last_valid_session || true)
    
    if [[ -n "$TARGET_SESSION" ]]; then
        tmux switch-client -t "$TARGET_SESSION"
    else
        # No valid session in history, try to find any non-git-monitor session
        FALLBACK_SESSION=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | \
                          grep -v "^git-monitor-" | \
                          grep -v "^$CURRENT_SESSION$" | \
                          head -1)
        
        if [[ -n "$FALLBACK_SESSION" ]]; then
            tmux switch-client -t "$FALLBACK_SESSION"
        else
            tmux display-message "No non-git-monitor session available"
        fi
    fi
else
    # We're in a regular session
    # First, add current session to history
    add_to_history "$CURRENT_SESSION"
    
    # Get the last non-git-monitor session
    TARGET_SESSION=$(get_last_valid_session || true)
    
    if [[ -n "$TARGET_SESSION" ]]; then
        tmux switch-client -t "$TARGET_SESSION"
    else
        # Fallback to tmux's built-in last session, but verify it's not git-monitor
        LAST_SESSION=$(tmux display-message -p '#{client_last_session}' 2>/dev/null || true)
        
        if [[ -n "$LAST_SESSION" ]] && [[ "$LAST_SESSION" != git-monitor-* ]]; then
            tmux switch-client -t "$LAST_SESSION"
        else
            # Find any other non-git-monitor session
            FALLBACK_SESSION=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | \
                              grep -v "^git-monitor-" | \
                              grep -v "^$CURRENT_SESSION$" | \
                              head -1)
            
            if [[ -n "$FALLBACK_SESSION" ]]; then
                tmux switch-client -t "$FALLBACK_SESSION"
            else
                tmux display-message "No other non-git-monitor session available"
            fi
        fi
    fi
fi