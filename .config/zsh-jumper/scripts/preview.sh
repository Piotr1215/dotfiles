#!/usr/bin/env bash
# zsh-jumper preview handler
# Receives: $1 = fzf selection (e.g., "[h] 6: DOC-1137")
set -eo pipefail

TOKEN="$1"
# Strip prefix: "[a] N: value" -> "value"
TOKEN="${TOKEN#*: }"
TOKEN="${TOKEN#\[*\] }"
# Strip quotes
TOKEN="${TOKEN//\"/}"
TOKEN="${TOKEN//\'/}"
# Handle VAR=value
[[ "$TOKEN" == *=* ]] && TOKEN="${TOKEN##*=}"
# Expand tilde
[[ "$TOKEN" == ~* ]] && TOKEN="$HOME${TOKEN#\~}"

export TOKEN

# Custom previewers (loaded from config at shell init)
# Check for Linear issue pattern
if [[ "$TOKEN" =~ (DEVOPS|DOC|ENG|IT)-[0-9]+ ]]; then
    ~/.config/zsh-jumper/scripts/linear-preview.sh 2>/dev/null && exit 0
fi

# Default: file/directory preview
if [ -d "$TOKEN" ]; then
    ls -la "$TOKEN" 2>/dev/null
elif [ -f "$TOKEN" ]; then
    if command -v bat >/dev/null; then
        bat --style=plain --color=always -n --line-range=:30 "$TOKEN" 2>/dev/null
    else
        head -30 "$TOKEN" 2>/dev/null
    fi
fi
