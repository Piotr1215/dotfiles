#!/usr/bin/env bash

# SessionStart hook for Claude Code
# This script reads and displays the norm-rules.md file at session start
# to ensure Claude understands and follows the rules in each session

RULES_FILE="/home/decoder/.claude/commands/norm-rules.md"

echo "ensure to read content of $RULES_FILE"

# Check if running in Neovim terminal
if [ -n "$NVIM" ]; then
    echo "You are running in context-awareness mode. I will automatically send you git diffs when I save files. These are FYI updates only - you don't need to respond or take any action unless I explicitly ask you a question. Just acknowledge that you understand this mode and wait for my questions."
fi
