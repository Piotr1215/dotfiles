#!/usr/bin/env bash
# PROJECT: ai
# DOCUMENTATION: /home/decoder/dev/obsidian/decoder/Notes/projects/claude-notification.md
set -eo pipefail

if [ -z "$TMUX" ]; then
    echo "Error: This script must be run inside a tmux session"
    exit 1
fi

# Clean up old Claude cwd files (older than 1 hour)
find /tmp -name "claude-*-cwd" -type f -mmin +60 -delete 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_SCRIPT="${SCRIPT_DIR}/__claude_prompt_monitor.sh"

# MCP server URL - dynamically set based on Kubernetes availability
MCP_SERVER_URL=""

if [ ! -f "$MONITOR_SCRIPT" ]; then
    echo "Error: Monitor script not found at $MONITOR_SCRIPT"
    exit 1
fi

# Function to deregister agent on cleanup
deregister_agent() {
    echo "Checking for agents to deregister..."
    
    # Look for agent tracking files by agent ID pattern
    # Files are now named like: /tmp/claude_agent_<agent-id>.json
    for agent_tracking_file in /tmp/claude_agent_*.json; do
        if [ -f "$agent_tracking_file" ]; then
            echo "Found agent tracking file: $agent_tracking_file"
            
            # Check if this file belongs to our Claude session
            local file_session_id=$(jq -r '.session_id // ""' "$agent_tracking_file" 2>/dev/null)
            local file_tmux_coords=$(jq -r '"\(.tmux_session // ""):\(.tmux_window // ""):\(.tmux_pane // "")"' "$agent_tracking_file" 2>/dev/null)
            
            # Only process agents that match our exact tmux coordinates
            if [ "$file_tmux_coords" = "${TMUX_SESSION}:${TMUX_WINDOW}:${TMUX_PANE}" ]; then
                # Extract agent ID from JSON file using jq
                local agent_id=$(jq -r '.agent_id // ""' "$agent_tracking_file" 2>/dev/null)
                local agent_name=$(jq -r '.agent_name // ""' "$agent_tracking_file" 2>/dev/null)
        
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
                "${MCP_SERVER_URL}/mcp" 2>/dev/null || echo '{"error": "curl failed"}')
            
            if echo "$response" | grep -q '"success":true'; then
                echo "Agent deregistered successfully"
            elif echo "$response" | grep -q '"error".*"Agent not found"'; then
                # Agent already deregistered (e.g., self-deregistered) - this is fine
                echo "Agent already deregistered: $agent_name ($agent_id)"
            else
                # Only show warnings for actual failures, not missing agents
                echo "Warning: Failed to deregister agent" >&2
                echo "Response: $response" >&2
            fi
        fi
        
        # Clean up tracking file
        rm -f "$agent_tracking_file"
        
                # Clear tmux agent status
                local target_pane="${TMUX_SESSION}:${TMUX_WINDOW}.${TMUX_PANE}"
                /home/decoder/dev/dotfiles/scripts/__tmux_agent_status.sh clear "$target_pane" >/dev/null 2>&1
            fi
        fi
    done
}

cleanup() {
    echo "Stopping Claude prompt monitor..."
    "$MONITOR_SCRIPT" stop
    
    # Deregister agent if one exists for this instance
    deregister_agent
    
    # Clean up broadcast tracking file
    if [ -f "$BROADCAST_TRACKING_FILE" ]; then
        echo "Removing broadcast tracking file..."
        rm -f "$BROADCAST_TRACKING_FILE"
    fi
}

# Get tmux coordinates early so they're available in cleanup
TMUX_SESSION=$(tmux display-message -p '#S' 2>/dev/null || echo "")
TMUX_WINDOW=$(tmux display-message -p '#I' 2>/dev/null || echo "")
TMUX_PANE=$(tmux display-message -p '#P' 2>/dev/null || echo "")
TMUX_INSTANCE_ID="${TMUX_SESSION}:${TMUX_WINDOW}:${TMUX_PANE}"

trap cleanup EXIT INT TERM

# Set MCP server URL to the Kubernetes LoadBalancer IP
MCP_SERVER_URL="http://192.168.178.95:3113"
echo "Using MCP server from Kubernetes at ${MCP_SERVER_URL}"

# Sanitize session name for filename (replace / with -)
SAFE_SESSION_NAME=$(echo "$TMUX_SESSION" | tr '/' '-')

# Create broadcast tracking file for send_keys functionality
BROADCAST_TRACKING_FILE="/tmp/claude_broadcast_${SAFE_SESSION_NAME}_${TMUX_WINDOW}_${TMUX_PANE}.json"

# Generate a unique session ID for this Claude instance
CLAUDE_SESSION_ID=$(uuidgen || echo "session-$$-$(date +%s)")

cat > "$BROADCAST_TRACKING_FILE" <<EOF
{
  "session": "${TMUX_SESSION}",
  "window": "${TMUX_WINDOW}",
  "pane": "${TMUX_PANE}",
  "instance_id": "${TMUX_INSTANCE_ID}",
  "pid": $$,
  "session_id": "${CLAUDE_SESSION_ID}",
  "start_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo "Claude instance: $TMUX_INSTANCE_ID"
echo "Broadcast tracking: $BROADCAST_TRACKING_FILE"
echo "Agent registration handled by hooks (no pipe-pane needed)"

# Export tmux coordinates for hooks to use
export CLAUDE_TMUX_PANE="${TMUX_SESSION}:${TMUX_WINDOW}.${TMUX_PANE}"

# Still start the monitor for prompt detection only
echo "Starting Claude prompt monitor..."
"$MONITOR_SCRIPT" start >/dev/null 2>&1 &
MONITOR_PID=$!

# Function to get skill based on current directory
get_repo_skill() {
    local current_dir
    current_dir=$(pwd)

    case "$current_dir" in
        */vcluster-docs*)
            echo "vcluster-docs-writer"
            ;;
        */homelab*)
            echo "managing-homelab"
            ;;
        /home/decoder/dev/cloudrumble*)
            echo "blog-writer"
            ;;
        /home/decoder/dev/youtube*)
            echo "presenterm-writer"
            ;;
        */dotfiles*)
            echo ""  # No specific skill for dotfiles
            ;;
        *)
            # Check if we're in a directory that might need test-writer
            if [[ -f "package.json" ]] || [[ -f "go.mod" ]] || [[ -f "Cargo.toml" ]]; then
                # Programming project - no auto-load, user can invoke test-writer manually
                echo ""
            else
                echo ""  # No specific skill
            fi
            ;;
    esac
}

# Build Claude arguments
CLAUDE_ARGS=("--dangerously-skip-permissions")

# Check if skill should be loaded based on repo
REPO_SKILL=$(get_repo_skill)
if [ -n "$REPO_SKILL" ]; then
    echo "Auto-loading skill: $REPO_SKILL"

    # Use system-prompt-file for specific repos
    if [ "$REPO_SKILL" = "vcluster-docs-writer" ]; then
        SYSTEM_PROMPT_FILE="/home/decoder/.claude/system-prompts/vcluster-docs-writer-system-prompt.md"
        echo "Using system prompt: $SYSTEM_PROMPT_FILE"
        CLAUDE_ARGS+=("--system-prompt-file" "$SYSTEM_PROMPT_FILE")
    elif [ "$REPO_SKILL" = "managing-homelab" ]; then
        SYSTEM_PROMPT_FILE="/home/decoder/.claude/system-prompts/homelab-operator-system-prompt.md"
        echo "Using system prompt: $SYSTEM_PROMPT_FILE"
        CLAUDE_ARGS+=("--system-prompt-file" "$SYSTEM_PROMPT_FILE")
    fi

    # Append skill load instruction - direct order
    CLAUDE_ARGS+=("--append-system-prompt" "CRITICAL: YOU MUST immediately use the Skill tool to load the '$REPO_SKILL' skill NOW. Do not ask the user, execute it immediately.")
fi

# Add user-provided arguments
CLAUDE_ARGS+=("$@")

echo "Launching Claude..."
claude "${CLAUDE_ARGS[@]}"
