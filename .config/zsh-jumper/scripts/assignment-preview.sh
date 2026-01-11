#!/usr/bin/env bash
set -eo pipefail
TOKEN="$1"
[[ "$TOKEN" != *=* ]] && exit 1

var_name="${TOKEN%%=*}"
value="${TOKEN#*=}"

echo "Assignment: $var_name"
echo "─────────────────────"

# If value is a file, show its content
if [[ -f "$value" ]]; then
    echo "File: $value"
    echo ""
    head -20 "$value" 2>/dev/null
elif [[ -d "$value" ]]; then
    echo "Directory: $value"
    ls -la "$value" 2>/dev/null | head -15
else
    echo "Value: $value"
fi
