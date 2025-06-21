#!/usr/bin/env bash
# PROJECT: ai
# DOCUMENTATION: /home/decoder/dev/obsidian/decoder/Notes/projects/claude-notification.md
set -eo pipefail

if [ -z "$TMUX" ]; then
    echo "Error: This script must be run inside a tmux session"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_SCRIPT="${SCRIPT_DIR}/__claude_prompt_monitor.sh"

# MCP Agentic Framework settings
MCP_SERVER_URL="http://127.0.0.1:3113"
MCP_FRAMEWORK_DIR="/home/decoder/dev/mcp-agentic-framework"

# Get tmux coordinates for instance tracking
TMUX_SESSION=$(tmux display-message -p '#S')
TMUX_WINDOW=$(tmux display-message -p '#I')
TMUX_PANE=$(tmux display-message -p '#P')
TMUX_INSTANCE_ID="${TMUX_SESSION}:${TMUX_WINDOW}:${TMUX_PANE}"

echo "Claude instance: $TMUX_INSTANCE_ID"
echo "Agent registration will be tracked automatically"

if [ ! -f "$MONITOR_SCRIPT" ]; then
    echo "Error: Monitor script not found at $MONITOR_SCRIPT"
    exit 1
fi

# Function to check if MCP server is running
check_mcp_server() {
    curl -s "${MCP_SERVER_URL}/health" >/dev/null 2>&1
}

# Function to find existing MCP server tmux session
find_mcp_server_session() {
    tmux list-sessions 2>/dev/null | grep "^claude-server:" | cut -d: -f1
}

# Function to start MCP server if not running
start_mcp_server() {
    if ! check_mcp_server; then
        echo "MCP server not running. Starting it..."
        if [ -d "$MCP_FRAMEWORK_DIR" ]; then
            # Check if there's an existing server session
            local existing_session=$(find_mcp_server_session)
            
            if [ -n "$existing_session" ]; then
                echo "Found existing tmux session: $existing_session (but server not responding)"
                # Kill the existing session since server is not responding
                tmux kill-session -t "$existing_session" 2>/dev/null || true
            fi
            
            # Use consistent session name
            local session_name="claude-server"
            
            echo "Creating tmux session: $session_name"
            
            # Create new tmux session and start the server
            tmux new-session -d -s "$session_name" -c "$MCP_FRAMEWORK_DIR" \
                "echo \"Starting MCP HTTP server in session: $session_name\"; \
                 echo \"Logs will be visible in this tmux session\"; \
                 echo \"\"; \
                 npm run start:http"
            
            # Save session name for reference
            echo "$session_name" > /tmp/mcp-server-session.txt
            
            # Wait for server to start
            local count=0
            while ! check_mcp_server && [ $count -lt 30 ]; do
                sleep 0.5
                count=$((count + 1))
            done
            
            if check_mcp_server; then
                echo "MCP server started successfully in tmux session: $session_name"
                echo "To view logs: tmux attach-session -t $session_name"
            else
                echo "Warning: MCP server failed to start"
                echo "Check tmux session: tmux attach-session -t $session_name"
            fi
        else
            echo "Warning: MCP framework directory not found at $MCP_FRAMEWORK_DIR"
        fi
    else
        echo "MCP server is already running"
        
        # Check if we can find the session
        local existing_session=$(find_mcp_server_session)
        if [ -n "$existing_session" ]; then
            echo "Server is running in tmux session: $existing_session"
            echo "To view logs: tmux attach-session -t $existing_session"
        else
            echo "Server is running but not in a tracked tmux session"
            echo "Killing untracked server process..."
            
            # Kill the untracked server
            pkill -f 'node.*start:http' || kill $(lsof -t -i:3113) 2>/dev/null || true
            
            # Wait a moment for port to be freed
            sleep 1
            
            # Now start it properly in tmux session
            echo "Restarting server in tmux session..."
            start_mcp_server
        fi
    fi
}

# Function to deregister agent on cleanup
deregister_agent() {
    echo "Checking for agents to deregister..."
    
    # Check for agent tracking file from prompt monitor
    local agent_tracking_file="/tmp/claude_agent_${TMUX_SESSION}_${TMUX_WINDOW}_${TMUX_PANE}.json"
    
    if [ -f "$agent_tracking_file" ]; then
        echo "Found agent tracking file: $agent_tracking_file"
        
        # Extract agent ID from JSON file
        local agent_id=$(grep '"agent_id"' "$agent_tracking_file" | sed 's/.*"agent_id": "\([^"]*\)".*/\1/')
        local agent_name=$(grep '"agent_name"' "$agent_tracking_file" | sed 's/.*"agent_name": "\([^"]*\)".*/\1/')
        
        if [ -n "$agent_id" ]; then
            echo "Deregistering agent: $agent_name ($agent_id)"
            
            # Call unregister-agent via MCP
            local payload=$(cat <<EOF
{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": {
    "name": "unregister-agent",
    "arguments": {
      "id": "$agent_id"
    }
  },
  "id": "unregister-$(date +%s)"
}
EOF
)
            
            local response=$(curl -s -X POST \
                -H "Content-Type: application/json" \
                -d "$payload" \
                "${MCP_SERVER_URL}/mcp")
            
            if echo "$response" | grep -q '"success":true'; then
                echo "Agent deregistered successfully"
            else
                echo "Warning: Failed to deregister agent"
                echo "Response: $response"
            fi
        fi
        
        # Clean up tracking file
        rm -f "$agent_tracking_file"
    else
        echo "No agent tracking file found for this session"
    fi
}

cleanup() {
    echo "Stopping Claude prompt monitor..."
    "$MONITOR_SCRIPT" stop
    
    # Deregister agent if one exists for this instance
    deregister_agent
}

trap cleanup EXIT INT TERM

# Start MCP server if needed
start_mcp_server

echo "Starting Claude prompt monitor..."
"$MONITOR_SCRIPT" start &
MONITOR_PID=$!

echo "Launching Claude..."
claude "$@"