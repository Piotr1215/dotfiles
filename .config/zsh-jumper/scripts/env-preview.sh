#!/usr/bin/env bash
set -eo pipefail

TOKEN="$1"

# Strip quotes (token comes raw from buffer)
TOKEN="${TOKEN#\"}"
TOKEN="${TOKEN%\"}"
TOKEN="${TOKEN#\'}"
TOKEN="${TOKEN%\'}"

var_name="${TOKEN#\$}"
var_name="${var_name#\{}"
var_name="${var_name%\}}"

[[ -z "$var_name" ]] && exit 0

value="${!var_name}"

echo "Variable: $var_name"
echo "─────────────────────"
if [[ -n "$value" ]]; then
    echo "$value"
else
    echo "(not set)"
fi
