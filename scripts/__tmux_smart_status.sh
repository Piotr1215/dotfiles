#!/usr/bin/env bash
# Smart status display: Shows active task or last command
set -eo pipefail

# Get active task if any
get_active_task() {
    if ! command -v task &> /dev/null; then
        echo ""
        return
    fi
    
    # Get tasks that have a start timestamp (actually started)
    local task_json=$(task rc.verbose=nothing status:pending start.any: export 2>/dev/null | jq -r 'sort_by(.start) | reverse | .[0]' 2>/dev/null)
    
    if [ -n "$task_json" ] && [ "$task_json" != "null" ]; then
        # Extract linear_issue_id from JSON
        local linear_id=$(echo "$task_json" | jq -r '.linear_issue_id // empty')
        
        if [ -n "$linear_id" ]; then
            echo "📋 $linear_id"
            return 0
        fi
    fi
    return 1
}

# Get last command from pane
get_last_command() {
    # Get the last command from shell history in the active pane
    local last_lines=$(tmux capture-pane -p -S -10 | tac)
    
    # Look for a command prompt pattern ($ or ❯ or >) followed by a command
    local last_cmd=$(echo "$last_lines" | grep -E '[$❯>]\s+[^$❯>]' | head -1 | sed -E 's/^.*[$❯>]\s+//')
    
    if [ -n "$last_cmd" ]; then
        # Truncate if too long
        if [ ${#last_cmd} -gt 30 ]; then
            last_cmd="${last_cmd:0:27}..."
        fi
        echo "$ $last_cmd"
    else
        # Fallback to current running command
        local current_cmd=$(tmux display-message -p '#{pane_current_command}')
        if [ "$current_cmd" != "zsh" ] && [ "$current_cmd" != "bash" ] && [ "$current_cmd" != "fish" ]; then
            # Truncate if needed
            if [ ${#current_cmd} -gt 20 ]; then
                current_cmd="${current_cmd:0:17}..."
            fi
            echo "▶ $current_cmd"
        else
            echo "💤 idle"
        fi
    fi
}

# Main logic - show both task and command
task_info=$(get_active_task || true)
cmd_info=$(get_last_command || true)

# Combine both pieces of information
if [ -n "$task_info" ] && [ -n "$cmd_info" ]; then
    echo "$task_info | $cmd_info"
elif [ -n "$task_info" ]; then
    echo "$task_info"
elif [ -n "$cmd_info" ]; then
    echo "$cmd_info"
else
    echo ""
fi