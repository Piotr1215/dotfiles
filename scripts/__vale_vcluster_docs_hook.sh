#!/usr/bin/env bash
set -e

# Read input
INPUT=$(cat)

# Extract file path
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

# Check if file is in vcluster-docs directory
if [[ ! "$FILE_PATH" =~ ^/home/decoder/loft/vcluster-docs/ ]]; then
    # File is not in vcluster-docs, exit silently
    exit 0
fi

# Get human-readable output (vale returns non-zero on errors/warnings)
vale_output=$(vale --config=/home/decoder/loft/vcluster-docs/.vale.ini "$FILE_PATH" 2>&1 || true)

# Get JSON output to check for severity
vale_json=$(vale --config=/home/decoder/loft/vcluster-docs/.vale.ini --output=JSON "$FILE_PATH" 2>&1 || true)

# Count errors and warnings using jq
errors_warnings=$(echo "$vale_json" | jq -r '
    to_entries | 
    map(.value) | 
    flatten | 
    map(select(.Severity == "error" or .Severity == "warning")) | 
    length
' 2>/dev/null || echo "0")

# If there are errors or warnings, provide feedback
if [ "$errors_warnings" -gt 0 ]; then
    # Return JSON with feedback for PostToolUse
    # Use "block" to indicate issues were found (even though PostToolUse can't actually block)
    reason="Vale found style issues:\n\n$vale_output"
    jq -n --arg reason "$reason" '{decision: "block", reason: $reason}'
    exit 2
fi

# No issues found
exit 0
