#!/usr/bin/env bash
# Display last command from current tmux pane
set -eo pipefail

get_last_command() {
    # Get the last command from shell history in the active pane
    # This captures the last few lines and extracts the command
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
        if [ "$current_cmd" != "zsh" ] && [ "$current_cmd" != "bash" ]; then
            echo "▶ $current_cmd"
        else
            echo ""
        fi
    fi
}

# Main
get_last_command