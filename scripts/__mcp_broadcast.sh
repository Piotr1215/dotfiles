#!/bin/bash
# MCP Broadcast CLI - Send any command output or file content as broadcast
# Usage: command | mcp-broadcast [options]
#        mcp-broadcast [options] < file
#        echo "message" | mcp-broadcast [options]

# Default values
SERVER_URL="${MCP_SERVER_URL:-http://192.168.178.91:3113}"
API_KEY="${MCP_EXTERNAL_API_KEY:-test-key-123}"
FROM="${MCP_BROADCAST_FROM:-human}"
PRIORITY="high"
SHOW_HELP=0
VERBOSE=0
STRIP_ANSI=1

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--from)
            FROM="$2"
            shift 2
            ;;
        -p|--priority)
            PRIORITY="$2"
            shift 2
            ;;
        -k|--api-key)
            API_KEY="$2"
            shift 2
            ;;
        -s|--server)
            SERVER_URL="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        --keep-colors)
            STRIP_ANSI=0
            shift
            ;;
        -h|--help)
            SHOW_HELP=1
            shift
            ;;
        *)
            echo "Unknown option: $1"
            SHOW_HELP=1
            shift
            ;;
    esac
done

# Show help if requested
if [ $SHOW_HELP -eq 1 ]; then
    cat << EOF
MCP Broadcast CLI - Send any output as broadcast to MCP agents

Usage:
    command | mcp-broadcast [options]
    mcp-broadcast [options] < file
    echo "message" | mcp-broadcast [options]

Options:
    -f, --from NAME      Sender name (default: external-broadcast)
    -p, --priority LEVEL Priority: low/normal/high (default: normal)
    -k, --api-key KEY    API key (default: test-key-123)
    -s, --server URL     Server URL (default: http://192.168.178.91:3113)
    -v, --verbose        Show detailed output
    --keep-colors        Keep ANSI color codes (default: strip them)
    -h, --help           Show this help message

Environment Variables:
    MCP_SERVER_URL       Server URL
    MCP_EXTERNAL_API_KEY API key for authentication
    MCP_BROADCAST_FROM   Default sender name

Examples:
    # Send command output
    df -h | mcp-broadcast -f "disk-monitor" -p high
    
    # Send file content
    mcp-broadcast -f "log-analyzer" < /var/log/app.log
    
    # Send inline message
    echo "Backup completed" | mcp-broadcast -f "backup-script"
    
    # Monitor log file
    tail -f /var/log/syslog | grep ERROR | mcp-broadcast -f "error-monitor" -p high
    
    # Send git commit info
    git log -1 --oneline | mcp-broadcast -f "git-hooks"
    
    # Send system status
    uptime | mcp-broadcast -f "system-monitor"

EOF
    exit 0
fi

# Read input from stdin
if [ -t 0 ]; then
    echo "Error: No input provided. Pipe data or redirect from file."
    echo "Use -h or --help for usage information."
    exit 1
fi

# Collect all input
if [ $STRIP_ANSI -eq 1 ]; then
    # Strip ANSI escape sequences (color codes)
    MESSAGE=$(cat | sed -r "s/\x1b\[[0-9;]*m//g")
else
    # Keep colors
    MESSAGE=$(cat)
fi

# Check if message is empty
if [ -z "$MESSAGE" ]; then
    echo "Error: Empty message"
    exit 1
fi

# Escape the message for JSON
# This handles quotes, newlines, and other special characters
ESCAPED_MESSAGE=$(echo "$MESSAGE" | jq -Rs .)

# Create JSON payload
JSON_PAYLOAD=$(jq -n \
    --arg from "$FROM" \
    --argjson message "$ESCAPED_MESSAGE" \
    --arg priority "$PRIORITY" \
    '{from: $from, message: $message, priority: $priority}')

# Show verbose info if requested
if [ $VERBOSE -eq 1 ]; then
    echo "Sending broadcast to: $SERVER_URL/external/broadcast"
    echo "From: $FROM"
    echo "Priority: $PRIORITY"
    echo "Message length: ${#MESSAGE} characters"
    echo "---"
fi

# Send the broadcast
RESPONSE=$(curl -s -X POST "$SERVER_URL/external/broadcast" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $API_KEY" \
    -d "$JSON_PAYLOAD")

# Check response
SUCCESS=$(echo "$RESPONSE" | jq -r '.success // false')

if [ "$SUCCESS" = "true" ]; then
    if [ $VERBOSE -eq 1 ]; then
        echo "✅ Broadcast sent successfully!"
        echo "$RESPONSE" | jq .
    else
        # Silent success in pipe mode
        exit 0
    fi
else
    echo "❌ Broadcast failed:"
    echo "$RESPONSE" | jq .
    exit 1
fi
