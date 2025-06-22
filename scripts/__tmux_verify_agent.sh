#!/usr/bin/env bash
# Verify and update agent status for tmux panes - SECURE VERSION
# Fixed command injection vulnerabilities found by complaining-elf

set -euo pipefail

# Safe JSON field extraction without sed
extract_json_field() {
    local file="$1"
    local field="$2"
    
    if [ ! -f "$file" ]; then
        echo ""
        return
    fi
    
    # Use jq if available (most secure)
    if command -v jq >/dev/null 2>&1; then
        jq -r ".${field} // empty" "$file" 2>/dev/null || echo ""
        return
    fi
    
    # Fallback: Safe extraction using grep and cut
    # This avoids sed which can execute commands
    local value=$(grep -o "\"${field}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$file" 2>/dev/null | cut -d'"' -f4)
    echo "${value:-}"
}

# Validate pane format to prevent injection
validate_pane_format() {
    local pane="$1"
    # Valid format: session:window.pane (alphanumeric with : and .)
    if [[ ! "$pane" =~ ^[a-zA-Z0-9_-]+:[0-9]+\.[0-9]+$ ]]; then
        echo "Error: Invalid pane format: $pane" >&2
        return 1
    fi
    return 0
}

# Get all panes with their current agent names
verify_all_agents() {
    # Get all panes
    tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{@agent_name}' | while read -r pane agent_name; do
        if [ -n "$agent_name" ] && [ "$agent_name" != " " ]; then
            # Validate pane format
            if ! validate_pane_format "$pane"; then
                continue
            fi
            
            # Extract session, window, pane from format
            local session=$(echo "$pane" | cut -d: -f1)
            local window_pane=$(echo "$pane" | cut -d: -f2)
            local window=$(echo "$window_pane" | cut -d. -f1)
            local pane_idx=$(echo "$window_pane" | cut -d. -f2)
            
            # Check if tracking file exists
            local tracking_file="/tmp/claude_agent_${session}_${window}_${pane_idx}.json"
            
            if [ ! -f "$tracking_file" ]; then
                # No tracking file, clear the agent name
                echo "Clearing stale agent name for $pane (no tracking file)"
                tmux set-option -pt "$pane" @agent_name ""
            else
                # Verify the agent name matches - SECURE VERSION
                local tracked_name=$(extract_json_field "$tracking_file" "agent_name")
                if [ "$tracked_name" != "$agent_name" ]; then
                    echo "Updating agent name for $pane: $tracked_name"
                    tmux set-option -pt "$pane" @agent_name "$tracked_name"
                fi
            fi
        fi
    done
}

# Verify a specific pane
verify_pane() {
    local target_pane="$1"
    
    # Validate input
    if [ -z "$target_pane" ]; then
        echo "Error: No target pane specified" >&2
        return 1
    fi
    
    # Validate pane format
    if ! validate_pane_format "$target_pane"; then
        return 1
    fi
    
    # Get session, window, pane from target
    local session=$(echo "$target_pane" | cut -d: -f1)
    local window_pane=$(echo "$target_pane" | cut -d: -f2)
    local window=$(echo "$window_pane" | cut -d. -f1)
    local pane_idx=$(echo "$window_pane" | cut -d. -f2)
    
    # Check tracking file
    local tracking_file="/tmp/claude_agent_${session}_${window}_${pane_idx}.json"
    
    if [ -f "$tracking_file" ]; then
        # SECURE JSON extraction
        local agent_name=$(extract_json_field "$tracking_file" "agent_name")
        if [ -n "$agent_name" ]; then
            tmux set-option -pt "$target_pane" @agent_name "$agent_name"
            echo "Set agent name '$agent_name' for $target_pane"
        fi
    else
        # Clear agent name if no tracking file
        tmux set-option -upt "$target_pane" @agent_name 2>/dev/null
        echo "Cleared agent name for $target_pane (no tracking)"
    fi
}

# Clean up orphaned tracking files
cleanup_orphaned() {
    # Get all tracking files
    for tracking_file in /tmp/claude_agent_*.json; do
        [ -f "$tracking_file" ] || continue
        
        # Extract coordinates from filename using parameter expansion (safer)
        local filename=$(basename "$tracking_file")
        # Remove prefix and suffix safely
        local coords="${filename#claude_agent_}"
        coords="${coords%.json}"
        
        # Split coordinates safely
        local session="${coords%%_*}"
        local remainder="${coords#*_}"
        local window="${remainder%%_*}"
        local pane="${remainder#*_}"
        
        # Validate extracted values
        if [[ -z "$session" || -z "$window" || -z "$pane" ]]; then
            echo "Warning: Malformed tracking file name: $tracking_file" >&2
            continue
        fi
        
        # Check if pane exists
        if ! tmux list-panes -t "${session}:${window}.${pane}" >/dev/null 2>&1; then
            echo "Removing orphaned tracking file: $tracking_file"
            rm -f "$tracking_file"
        fi
    done
}

# Main command handling
case "${1:-}" in
    all)
        verify_all_agents
        ;;
    pane)
        verify_pane "$2"
        ;;
    cleanup)
        cleanup_orphaned
        ;;
    *)
        echo "Usage: $0 {all|pane <target>|cleanup}"
        echo "  all     - Verify all panes"
        echo "  pane    - Verify specific pane"
        echo "  cleanup - Remove orphaned tracking files"
        exit 1
        ;;
esac