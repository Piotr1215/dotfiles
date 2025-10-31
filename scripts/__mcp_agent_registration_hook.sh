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
    
    # Try multiple strategies to find the right broadcast file
    
    # Strategy 1: Check CLAUDE_TMUX_PANE environment variable (if set by parent)
    if [ -n "$CLAUDE_TMUX_PANE" ]; then
        echo "[$(date)] Found CLAUDE_TMUX_PANE env var: $CLAUDE_TMUX_PANE" >> /tmp/mcp-agent-hook.log
        echo "$CLAUDE_TMUX_PANE"
        return 0
    fi
    
    # Strategy 2: Find the most recently modified broadcast file (within last 60 seconds)
    local newest_file=""
    local newest_time=0
    
    for broadcast_file in /tmp/claude_broadcast_*.json; do
        if [ -f "$broadcast_file" ]; then
            # Get file modification time
            local file_time=$(stat -c %Y "$broadcast_file" 2>/dev/null || stat -f %m "$broadcast_file" 2>/dev/null)
            local current_time=$(date +%s)
            local age=$((current_time - file_time))
            
            # If file is less than 60 seconds old and newer than previous
            if [ $age -lt 60 ] && [ $file_time -gt $newest_time ]; then
                newest_file="$broadcast_file"
                newest_time=$file_time
            fi
        fi
    done
    
    if [ -n "$newest_file" ]; then
        echo "[$(date)] Using newest broadcast file: $newest_file (age: $(($(date +%s) - newest_time))s)" >> /tmp/mcp-agent-hook.log
        
        # Extract tmux info from the newest file
        local tmux_session=$(jq -r '.session // ""' "$newest_file")
        local tmux_window=$(jq -r '.window // ""' "$newest_file")
        local tmux_pane=$(jq -r '.pane // ""' "$newest_file")
        
        if [ -n "$tmux_session" ] && [ -n "$tmux_window" ] && [ -n "$tmux_pane" ]; then
            echo "$tmux_session:$tmux_window:$tmux_pane"
            return 0
        fi
    fi
    
    return 1
}

echo "[$(date)] Hook called with tool: $TOOL_NAME" >> /tmp/mcp-agent-hook.log

case "$TOOL_NAME" in
    "mcp__agentic-framework__register-agent")
        echo "[$(date)] Processing agent registration..." >> /tmp/mcp-agent-hook.log
        
        # Check if this is the first agent being registered
        # Count files more safely
        if [ -d /tmp ]; then
            EXISTING_AGENTS=0
            for f in /tmp/claude_agent_*.json; do
                [ -e "$f" ] && EXISTING_AGENTS=$((EXISTING_AGENTS + 1))
            done
            echo "[$(date)] Existing agents count: $EXISTING_AGENTS" >> /tmp/mcp-agent-hook.log
        else
            echo "[$(date)] ERROR: /tmp directory not accessible" >> /tmp/mcp-agent-hook.log
            EXISTING_AGENTS=1  # Assume not first to be safe
        fi
        
        # If no agents exist, this is the first registration - open web UI
        if [ "$EXISTING_AGENTS" -eq 0 ]; then
            echo "[$(date)] First agent registration detected - opening MCP web UI" >> /tmp/mcp-agent-hook.log
            # Try to get DISPLAY from current user's environment
            if [ -z "$DISPLAY" ]; then
                # Try to get it from the user's process
                USER_DISPLAY=$(ps e -u $USER | grep -o 'DISPLAY=[^ ]*' | head -1 | cut -d= -f2)
                export DISPLAY="${USER_DISPLAY:-:1}"
                echo "[$(date)] Set DISPLAY=$DISPLAY" >> /tmp/mcp-agent-hook.log
            else
                echo "[$(date)] DISPLAY already set to: $DISPLAY" >> /tmp/mcp-agent-hook.log
            fi
            echo "[$(date)] Attempting to open browser with firefox..." >> /tmp/mcp-agent-hook.log
            nohup firefox "http://192.168.178.95:3113" > /dev/null 2>&1 &
            echo "[$(date)] firefox command executed" >> /tmp/mcp-agent-hook.log
        else
            echo "[$(date)] Not first agent - existing agents: $EXISTING_AGENTS" >> /tmp/mcp-agent-hook.log
        fi
        
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
                # Parse coordinates (format: session:window.pane)
                TMUX_SESSION=$(echo "$TMUX_COORDS" | cut -d: -f1)
                WINDOW_PANE=$(echo "$TMUX_COORDS" | cut -d: -f2)
                TMUX_WINDOW=$(echo "$WINDOW_PANE" | cut -d. -f1)
                TMUX_PANE=$(echo "$WINDOW_PANE" | cut -d. -f2)
                
                # Create agent tracking file using agent ID as the key
                # This prevents multiple agents from overwriting each other
                SAFE_AGENT_ID=$(echo "$AGENT_ID" | tr '/' '-')
                AGENT_TRACKING_FILE="/tmp/claude_agent_${SAFE_AGENT_ID}.json"
                
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
                
                # Update tmux status with error checking
                TARGET_PANE="${TMUX_SESSION}:${TMUX_WINDOW}.${TMUX_PANE}"
                if [ -x "/home/decoder/dev/dotfiles/scripts/__tmux_agent_status.sh" ]; then
                    echo "[$(date)] Setting tmux name '$AGENT_NAME' for pane $TARGET_PANE" >> /tmp/mcp-agent-hook.log
                    
                    # Try to set the agent name and capture result
                    if /home/decoder/dev/dotfiles/scripts/__tmux_agent_status.sh set "$AGENT_NAME" "$TARGET_PANE" 2>>/tmp/mcp-agent-hook.log; then
                        # Verify it was actually set
                        VERIFY_NAME=$(tmux display-message -pt "$TARGET_PANE" '#{@agent_name}' 2>/dev/null || echo "")
                        if [ "$VERIFY_NAME" = "$AGENT_NAME" ]; then
                            echo "[$(date)] Successfully verified agent name in tmux" >> /tmp/mcp-agent-hook.log
                        else
                            echo "[$(date)] WARNING: Tmux name verification failed! Expected '$AGENT_NAME', got '$VERIFY_NAME'" >> /tmp/mcp-agent-hook.log
                            # Try direct tmux command as fallback
                            tmux set-option -pt "$TARGET_PANE" @agent_name "$AGENT_NAME" 2>>/tmp/mcp-agent-hook.log
                        fi
                    else
                        echo "[$(date)] ERROR: Failed to set tmux agent name!" >> /tmp/mcp-agent-hook.log
                    fi
                fi
                
                echo "[$(date)] Agent registered: $AGENT_NAME ($AGENT_ID) in $TARGET_PANE" >> /tmp/mcp-agent-hook.log

                # Update broadcast file with agent name for future reference
                SAFE_SESSION_NAME=$(echo "$TMUX_SESSION" | tr '/' '-')
                broadcast_file="/tmp/claude_broadcast_${SAFE_SESSION_NAME}_${TMUX_WINDOW}_${TMUX_PANE}.json"
                if [ -f "$broadcast_file" ]; then
                    # Add agent_name to the broadcast file
                    temp_file="${broadcast_file}.tmp"
                    jq --arg agent "$AGENT_NAME" '. + {agent_name: $agent}' "$broadcast_file" > "$temp_file" && mv "$temp_file" "$broadcast_file"
                    echo "[$(date)] Updated broadcast file with agent name: $AGENT_NAME" >> /tmp/mcp-agent-hook.log
                fi

                # Output success message for PostToolUse hook
                jq -n --arg reason "Agent '$AGENT_NAME' registered in tmux pane $TARGET_PANE" '{"reason": $reason}'
            else
                echo "[$(date)] Agent registered: $AGENT_NAME ($AGENT_ID) - no broadcast file found" >> /tmp/mcp-agent-hook.log

                # Fallback: Try to set agent name in current tmux pane if we're in tmux
                if [ -n "$TMUX" ]; then
                    echo "[$(date)] Attempting fallback: setting name in current tmux pane" >> /tmp/mcp-agent-hook.log
                    CURRENT_SESSION=$(tmux display-message -p '#S' 2>/dev/null)
                    CURRENT_WINDOW=$(tmux display-message -p '#I' 2>/dev/null)
                    CURRENT_PANE=$(tmux display-message -p '#P' 2>/dev/null)

                    if [ -n "$CURRENT_SESSION" ] && [ -n "$CURRENT_WINDOW" ] && [ -n "$CURRENT_PANE" ]; then
                        FALLBACK_PANE="${CURRENT_SESSION}:${CURRENT_WINDOW}.${CURRENT_PANE}"
                        tmux set-option -p @agent_name "$AGENT_NAME" 2>>/tmp/mcp-agent-hook.log
                        echo "[$(date)] Fallback: Set agent name in current pane $FALLBACK_PANE" >> /tmp/mcp-agent-hook.log

                        # Update tracking file with discovered coordinates
                        SAFE_AGENT_ID=$(echo "$AGENT_ID" | tr '/' '-')
                        AGENT_TRACKING_FILE="/tmp/claude_agent_${SAFE_AGENT_ID}.json"
                        cat > "$AGENT_TRACKING_FILE" <<EOF
{
  "agent_id": "$AGENT_ID",
  "agent_name": "$AGENT_NAME",
  "tmux_session": "$CURRENT_SESSION",
  "tmux_window": "$CURRENT_WINDOW",
  "tmux_pane": "$CURRENT_PANE",
  "instance_id": "fallback",
  "session_id": "$SESSION_ID",
  "registered_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
                        # Output success message for PostToolUse hook
                        jq -n --arg reason "Agent '$AGENT_NAME' registered in tmux pane $FALLBACK_PANE (fallback)" '{"reason": $reason}'
                    else
                        # No tmux coordinates found
                        jq -n --arg reason "Agent '$AGENT_NAME' registered (no tmux coordinates available)" '{"reason": $reason}'
                    fi
                else
                    # Not in tmux
                    jq -n --arg reason "Agent '$AGENT_NAME' registered (not in tmux session)" '{"reason": $reason}'
                fi
            fi
        else
            # No agent ID found
            echo "[$(date)] WARNING: No agent ID found in registration response" >> /tmp/mcp-agent-hook.log
            jq -n --arg reason "Agent registration completed (no agent ID in response)" '{"reason": $reason}'
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

                # Output success message for PostToolUse hook
                jq -n --arg reason "Agent '$AGENT_NAME' unregistered and tmux status cleared" '{"reason": $reason}'
            else
                echo "[$(date)] Agent unregistered: $AGENT_ID - no tracking file found" >> /tmp/mcp-agent-hook.log

                # Output success message even if no tracking file was found
                jq -n --arg reason "Agent unregistered (no tracking file found)" '{"reason": $reason}'
            fi
        else
            # No agent ID provided
            echo "[$(date)] WARNING: No agent ID provided for unregistration" >> /tmp/mcp-agent-hook.log
            jq -n --arg reason "Agent unregistration completed" '{"reason": $reason}'
        fi
        ;;

    *)
        # Unknown tool - no action needed
        echo "[$(date)] Hook called for unhandled tool: $TOOL_NAME" >> /tmp/mcp-agent-hook.log
        jq -n --arg reason "Hook executed (no action required for $TOOL_NAME)" '{"reason": $reason}'
        ;;
esac

exit 0