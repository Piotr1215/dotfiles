#!/usr/bin/env bash
set -eo pipefail

# Post-tool-use hook to run shellcheck on bash scripts
# Runs automatically after Write/Edit operations on .sh files or files with bash shebang

# Read input from Claude Code
INPUT=$(cat)

# Extract file path from JSON input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

# Exit silently if no file path
if [[ -z "$FILE_PATH" ]]; then
  jq -n '{decision: "allow"}'
  exit 0
fi

# Exit if file doesn't exist
if [[ ! -f "$FILE_PATH" ]]; then
  jq -n '{decision: "allow"}'
  exit 0
fi

# Check if file is a bash script
is_bash_script=false

# Check 1: File extension
if [[ "$FILE_PATH" == *.sh ]]; then
  is_bash_script=true
fi

# Check 2: Shebang
if [[ "$is_bash_script" == false ]]; then
  first_line=$(head -n 1 "$FILE_PATH" 2>/dev/null || true)
  if [[ "$first_line" =~ ^#!/.*bash ]]; then
    is_bash_script=true
  fi
fi

# Exit if not a bash script
if [[ "$is_bash_script" == false ]]; then
  jq -n '{decision: "allow"}'
  exit 0
fi

# Check if shellcheck is installed
if ! command -v shellcheck &> /dev/null; then
  reason="shellcheck is not installed. Install: apt install shellcheck"
  jq -n --arg reason "$reason" '{decision: "warn", reason: $reason}'
  exit 0
fi

# Run shellcheck and capture output
FILENAME=$(basename "$FILE_PATH")
shellcheck_output=$(shellcheck "$FILE_PATH" 2>&1 || true)
shellcheck_exit=$?

# Build diagnostic message
if [ $shellcheck_exit -eq 0 ]; then
  # No issues found
  jq -n '{decision: "allow"}'
  exit 0
else
  # Issues found - show them
  diagnostic="shellcheck found issues in $FILENAME:

$shellcheck_output

Fix these issues or review if they're acceptable."

  jq -n --arg reason "$diagnostic" '{
    decision: "warn",
    reason: $reason
  }'
  exit 0
fi
