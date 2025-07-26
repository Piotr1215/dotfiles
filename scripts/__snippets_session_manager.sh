#!/usr/bin/env bash

set -eo pipefail

# Constants
COMPOSITE_SESSION="snippets"

# Get the current session name (where M-c was triggered from)
get_current_session() {
    tmux display-message -p '#S'
}

# Get the current pane's directory
get_current_directory() {
    tmux display-message -p '#{pane_current_path}'
}

# Check if a window exists in composite session
window_exists() {
    local window_name="$1"
    tmux list-windows -t "$COMPOSITE_SESSION" -F '#W' 2>/dev/null | grep -q "^${window_name}$"
}

# Find an idle pane in a window (one showing shell prompt)
find_idle_pane() {
    local window_name="$1"
    local panes=$(tmux list-panes -t "$COMPOSITE_SESSION:$window_name" -F '#{pane_id}:#{pane_current_command}:#{pane_current_path}' 2>/dev/null)
    
    while IFS=':' read -r pane_id cmd pane_path; do
        # Check if pane is running a shell (bash, zsh, sh)
        if [[ "$cmd" =~ ^(bash|zsh|sh|fish)$ ]]; then
            # Get the last few lines to check for prompt
            local pane_content=$(tmux capture-pane -t "$pane_id" -p -S -5 | tail -n 5)
            # Check if there's no active command running (look for prompt patterns)
            # This checks for empty lines OR lines ending with common prompt characters
            if echo "$pane_content" | grep -qE '(^[[:space:]]*$|[$❯→>%#][[:space:]]*$|@[^:]+:[^$#]+[$#][[:space:]]*$)'; then
                echo "$pane_id"
                return 0
            fi
        fi
    done <<< "$panes"
    
    return 1
}

# Create composite session if it doesn't exist
ensure_composite_session() {
    if ! tmux has-session -t "$COMPOSITE_SESSION" 2>/dev/null; then
        # Get current session and directory for the first window
        local current_session=$(get_current_session)
        local current_dir=$(get_current_directory)
        
        # Create session with first window named after current session
        tmux new-session -d -s "$COMPOSITE_SESSION" -n "$current_session" -c "$current_dir"
    fi
}

# Execute command in composite session
execute_in_composite() {
    local originating_session="$1"
    local command="$2"
    local working_directory="$3"
    
    ensure_composite_session
    
    # Check if window for originating session exists
    if window_exists "$originating_session"; then
        # Try to find an idle pane
        if idle_pane=$(find_idle_pane "$originating_session"); then
            # Use the idle pane
            # Debug: Show which pane we're using
            # echo "Using idle pane: $idle_pane" >&2
            tmux send-keys -t "$idle_pane" "cd $working_directory && clear" C-m
            
            # Check if command has parameters (contains ?)
            if [[ "$command" =~ \? ]]; then
                # Send command without executing, so user can edit parameters
                tmux send-keys -t "$idle_pane" "$command"
            else
                # Execute command directly
                tmux send-keys -t "$idle_pane" "$command" C-m
            fi
            
            # Switch to the composite session and select the pane
            tmux switch-client -t "$COMPOSITE_SESSION:$originating_session"
            tmux select-pane -t "$idle_pane"
        else
            # No idle pane, create a new one
            # Get current number of panes
            local pane_count=$(tmux list-panes -t "$COMPOSITE_SESSION:$originating_session" | wc -l)
            
            # Create new pane based on count to maintain 2x2 grid
            if [ "$pane_count" -eq 1 ]; then
                # Split horizontally for second pane
                tmux split-window -h -t "$COMPOSITE_SESSION:$originating_session" -c "$working_directory"
            elif [ "$pane_count" -eq 2 ]; then
                # Split first pane vertically for third pane
                tmux split-window -v -t "$COMPOSITE_SESSION:$originating_session.1" -c "$working_directory"
            elif [ "$pane_count" -eq 3 ]; then
                # Split second pane vertically for fourth pane
                tmux split-window -v -t "$COMPOSITE_SESSION:$originating_session.2" -c "$working_directory"
            else
                # For more than 4 panes, just split the last pane
                tmux split-window -t "$COMPOSITE_SESSION:$originating_session" -c "$working_directory"
            fi
            
            # Apply tiled layout to maintain grid
            tmux select-layout -t "$COMPOSITE_SESSION:$originating_session" tiled
            
            local new_pane=$(tmux display-message -p -t "$COMPOSITE_SESSION:$originating_session" '#{pane_id}')
            
            # Clear and execute command in new pane
            tmux send-keys -t "$new_pane" "clear" C-m
            if [[ "$command" =~ \? ]]; then
                tmux send-keys -t "$new_pane" "$command"
            else
                tmux send-keys -t "$new_pane" "$command" C-m
            fi
            
            # Switch to composite session
            tmux switch-client -t "$COMPOSITE_SESSION:$originating_session"
        fi
    else
        # Create new window named after originating session
        tmux new-window -t "$COMPOSITE_SESSION" -n "$originating_session" -c "$working_directory"
        
        # Clear and execute command
        tmux send-keys -t "$COMPOSITE_SESSION:$originating_session" "clear" C-m
        if [[ "$command" =~ \? ]]; then
            tmux send-keys -t "$COMPOSITE_SESSION:$originating_session" "$command"
        else
            tmux send-keys -t "$COMPOSITE_SESSION:$originating_session" "$command" C-m
        fi
        
        # Switch to composite session
        tmux switch-client -t "$COMPOSITE_SESSION:$originating_session"
    fi
}

# Switch to composite session with smart window focus
switch_to_composite() {
    local originating_session="$1"
    local working_directory="$2"
    
    ensure_composite_session
    
    # Check if window for originating session exists
    if window_exists "$originating_session"; then
        # Switch to existing window
        tmux switch-client -t "$COMPOSITE_SESSION:$originating_session"
    else
        # Create new window for this session
        tmux new-window -t "$COMPOSITE_SESSION" -n "$originating_session" -c "$working_directory"
        tmux switch-client -t "$COMPOSITE_SESSION:$originating_session"
    fi
}

# Main logic
main() {
    local current_session=$(get_current_session)
    local current_directory=$(get_current_directory)
    
    # Check if we're being called with a command (from pet snippet)
    if [ -n "$1" ]; then
        # Execute command mode
        execute_in_composite "$current_session" "$1" "$current_directory"
    else
        # Just switch to composite mode
        switch_to_composite "$current_session" "$current_directory"
    fi
}

# Check if script is being sourced or executed
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi