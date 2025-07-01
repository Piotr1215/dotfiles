#!/usr/bin/env bash
# Hook script for MCP agent registration/unregistration
# Called by Claude hooks when register-agent or unregister-agent tools are used
set -eo pipefail

# Read JSON input from stdin
INPUT=$(cat)

# Extract tool name and session ID
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')

# Function to find tmux coordinates from session
find_tmux_coordinates() {
    local session_id="$1"
    
    # Look for broadcast tracking files that match this session
    for broadcast_file in /tmp/claude_broadcast_*.json; do
        if [ -f "$broadcast_file" ]; then
            # Check if file was created recently (within last hour)
            if [ -z "$(find "$broadcast_file" -mmin +60 2>/dev/null)" ]; then
                # Extract tmux info
                local tmux_session=$(jq -r '.session // ""' "$broadcast_file")
                local tmux_window=$(jq -r '.window // ""' "$broadcast_file")
                local tmux_pane=$(jq -r '.pane // ""' "$broadcast_file")
                
                if [ -n "$tmux_session" ] && [ -n "$tmux_window" ] && [ -n "$tmux_pane" ]; then
                    echo "$tmux_session:$tmux_window:$tmux_pane"
                    return 0
                fi
            fi
        fi
    done
    
    return 1
}

case "$TOOL_NAME" in
    "mcp__agentic-framework__register-agent")
        # Extract agent details
        AGENT_NAME=$(echo "$INPUT" | jq -r '.tool_input.name // "Unknown"')
        INSTANCE_ID=$(echo "$INPUT" | jq -r '.tool_input.instanceId // ""')
        
        # Extract agent ID from response
        RESPONSE_TEXT=$(echo "$INPUT" | jq -r '.tool_response[0].text // ""')
        AGENT_ID=$(echo "$RESPONSE_TEXT" | grep -oP 'agent-\d+-\w+' || echo "")
        
        if [ -n "$AGENT_ID" ]; then
            # Try to find tmux coordinates
            TMUX_COORDS=""
            
            # First try: Use instanceId if it contains tmux coordinates
            if [[ "$INSTANCE_ID" =~ ^([^:]+):([^:]+):([^:]+)$ ]]; then
                TMUX_COORDS="$INSTANCE_ID"
            else
                # Second try: Find from broadcast files
                TMUX_COORDS=$(find_tmux_coordinates "$SESSION_ID" || echo "")
            fi
            
            if [ -n "$TMUX_COORDS" ]; then
                # Parse coordinates
                IFS=':' read -r TMUX_SESSION TMUX_WINDOW TMUX_PANE <<< "$TMUX_COORDS"
                
                # Create agent tracking file using session ID as the key
                # This avoids pane number confusion
                SAFE_SESSION_ID=$(echo "$SESSION_ID" | tr -d ':' | tr '/' '-')
                AGENT_TRACKING_FILE="/tmp/claude_agent_${SAFE_SESSION_ID}.json"
                
                cat > "$AGENT_TRACKING_FILE" <<EOF
{
  "agent_id": "$AGENT_ID",
  "agent_name": "$AGENT_NAME",
  "tmux_session": "$TMUX_SESSION",
  "tmux_window": "$TMUX_WINDOW",
  "tmux_pane": "$TMUX_PANE",
  "instance_id": "$INSTANCE_ID",
  "session_id": "$SESSION_ID",
  "registered_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
                
                # Update tmux status
                TARGET_PANE="${TMUX_SESSION}:${TMUX_WINDOW}.${TMUX_PANE}"
                if [ -x "/home/decoder/dev/dotfiles/scripts/__tmux_agent_status.sh" ]; then
                    /home/decoder/dev/dotfiles/scripts/__tmux_agent_status.sh set "$AGENT_NAME" "$TARGET_PANE" >/dev/null 2>&1
                fi
                
                echo "[$(date)] Agent registered: $AGENT_NAME ($AGENT_ID) in $TARGET_PANE" >> /tmp/mcp-agent-hook.log
            else
                echo "[$(date)] Agent registered: $AGENT_NAME ($AGENT_ID) - no tmux coordinates found" >> /tmp/mcp-agent-hook.log
            fi
        fi
        ;;
        
    "mcp__agentic-framework__unregister-agent")
        # Extract agent ID
        AGENT_ID=$(echo "$INPUT" | jq -r '.tool_input.id // ""')
        
        if [ -n "$AGENT_ID" ]; then
            # Find and remove agent tracking file
            AGENT_FILE=$(grep -l "\"agent_id\": \"$AGENT_ID\"" /tmp/claude_agent_*.json 2>/dev/null | head -1)
            
            if [ -n "$AGENT_FILE" ]; then
                # Extract tmux info before removing
                TMUX_SESSION=$(jq -r '.tmux_session // ""' "$AGENT_FILE")
                TMUX_WINDOW=$(jq -r '.tmux_window // ""' "$AGENT_FILE")
                TMUX_PANE=$(jq -r '.tmux_pane // ""' "$AGENT_FILE")
                AGENT_NAME=$(jq -r '.agent_name // "Unknown"' "$AGENT_FILE")
                
                # Clear tmux status
                if [ -n "$TMUX_SESSION" ] && [ -n "$TMUX_WINDOW" ] && [ -n "$TMUX_PANE" ]; then
                    TARGET_PANE="${TMUX_SESSION}:${TMUX_WINDOW}.${TMUX_PANE}"
                    if [ -x "/home/decoder/dev/dotfiles/scripts/__tmux_agent_status.sh" ]; then
                        /home/decoder/dev/dotfiles/scripts/__tmux_agent_status.sh clear "$TARGET_PANE" >/dev/null 2>&1
                    fi
                fi
                
                # Remove tracking file
                rm -f "$AGENT_FILE"
                
                echo "[$(date)] Agent unregistered: $AGENT_NAME ($AGENT_ID)" >> /tmp/mcp-agent-hook.log
            else
                echo "[$(date)] Agent unregistered: $AGENT_ID - no tracking file found" >> /tmp/mcp-agent-hook.log
            fi
        fi
        ;;
esac

exit 0