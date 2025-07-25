#!/usr/bin/env bash
# Pre-tool-use hook for enforcing write-lock in MCP Agentic Framework
# Blocks write/edit operations when lock is active, except for fat-owl
# Security Model:
# - Checks /var/tmp/mcp-write-lock.json for global lock state
# - fat-owl is hard-coded exempt (knowledge custodian privilege)
# - Agent identity verified via /tmp/claude_agent_*.json tracking files
# - Returns exit code 2 to block operations when locked
set -eo pipefail

# Read JSON input from stdin
INPUT=$(cat)

# Extract tool name
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')

# Check if this is a write-related tool
# Updated pattern to catch both standard tools and MCP filesystem operations
case "$TOOL_NAME" in
    "Edit"|"Write"|"MultiEdit"|"mcp__filesystem__edit_file"|"mcp__filesystem__write_file")
        # This is a write operation, check if it's allowed
        ;;
    *)
        # Not a write operation, allow it
        exit 0
        ;;
esac

# Read lock state
LOCK_FILE="$HOME/.local/state/mcp-agentic-framework/write-lock.json"
if [ ! -f "$LOCK_FILE" ]; then
    # No lock file means unlocked
    exit 0
fi

# Parse lock state
LOCK_STATE=$(cat "$LOCK_FILE")
IS_LOCKED=$(echo "$LOCK_STATE" | jq -r '.locked // false')

if [ "$IS_LOCKED" != "true" ]; then
    # Not locked, allow operation
    exit 0
fi

# Lock is active, check if calling agent is fat-owl
# Try to extract agent information from the session or context
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')

# Function to check if current agent is fat-owl
is_fat_owl() {
    # Check agent tracking files
    for agent_file in /tmp/claude_agent_*.json; do
        if [ -f "$agent_file" ]; then
            AGENT_NAME=$(jq -r '.agent_name // ""' "$agent_file" 2>/dev/null || echo "")
            if [ "$AGENT_NAME" = "fat-owl" ]; then
                # Check if this session belongs to fat-owl
                AGENT_SESSION=$(jq -r '.session_id // ""' "$agent_file" 2>/dev/null || echo "")
                if [ "$AGENT_SESSION" = "$SESSION_ID" ]; then
                    return 0
                fi
            fi
        fi
    done
    
    # Also check environment variable (if set by agent registration hook)
    if [ "$CLAUDE_AGENT_NAME" = "fat-owl" ]; then
        return 0
    fi
    
    return 1
}

# Check if this is fat-owl
if is_fat_owl; then
    echo "[$(date)] Write-lock: Allowing fat-owl to bypass lock" >> /tmp/mcp-write-lock.log
    exit 0
fi

# Not fat-owl and lock is active - block the operation
LOCK_REASON=$(echo "$LOCK_STATE" | jq -r '.reason // "Write operations are currently locked"')

# Log the block
echo "[$(date)] Write-lock: Blocked $TOOL_NAME operation (not fat-owl)" >> /tmp/mcp-write-lock.log

# Return error with exit code 2 to block the operation
echo "Write operation blocked: $LOCK_REASON" >&2
exit 2