#!/usr/bin/env bash
# Manage tmux agent status display
set -eo pipefail

# Get tmux coordinates
get_tmux_coords() {
    local session=$(tmux display-message -p '#S')
    local window=$(tmux display-message -p '#I')
    local pane=$(tmux display-message -p '#P')
    echo "${session}:${window}:${pane}"
}

# Set agent name for current pane
set_agent_name() {
    local agent_name="$1"
    local target_pane="${2:-}"
    local coords=$(get_tmux_coords)
    
    if [ -n "$agent_name" ]; then
        # Set a per-pane user option
        if [ -n "$target_pane" ]; then
            tmux set-option -pt "$target_pane" @agent_name "$agent_name"
            echo "Set agent name '$agent_name' for $target_pane"
        else
            tmux set-option -p @agent_name "$agent_name"
            echo "Set agent name '$agent_name' for $coords"
        fi
    else
        echo "Error: No agent name provided"
        exit 1
    fi
}

# Clear agent name for current pane
clear_agent_name() {
    local target_pane="${1:-}"
    local coords=$(get_tmux_coords)
    
    if [ -n "$target_pane" ]; then
        tmux set-option -upt "$target_pane" @agent_name
        echo "Cleared agent name for $target_pane"
    else
        tmux set-option -up @agent_name
        echo "Cleared agent name for $coords"
    fi
}

# Main command handling
case "${1:-}" in
    set)
        set_agent_name "$2" "$3"
        ;;
    clear)
        clear_agent_name "$2"
        ;;
    get)
        tmux display-message -p '#{@agent_name}'
        ;;
    *)
        echo "Usage: $0 {set <name>|clear|get}"
        exit 1
        ;;
esac