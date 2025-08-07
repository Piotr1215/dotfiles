#!/usr/bin/env bash

# SessionStart hook for Claude Code
# This script reads and displays the norm-rules.md file at session start
# to ensure Claude understands and follows the rules in each session

RULES_FILE="/home/decoder/.claude/commands/norm-rules.md"

if [[ -f "$RULES_FILE" ]]; then
    cat "$RULES_FILE"
else
    echo "Warning: Rules file not found at $RULES_FILE"
fi