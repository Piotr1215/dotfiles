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

if [ ! -f "$MONITOR_SCRIPT" ]; then
    echo "Error: Monitor script not found at $MONITOR_SCRIPT"
    exit 1
fi

cleanup() {
    echo "Stopping Claude prompt monitor..."
    "$MONITOR_SCRIPT" stop
}

trap cleanup EXIT INT TERM

echo "Starting Claude prompt monitor..."
"$MONITOR_SCRIPT" start &
MONITOR_PID=$!

sleep 0.5

echo "Launching Claude..."
claude "$@"