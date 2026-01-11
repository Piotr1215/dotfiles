#!/usr/bin/env bash
# zsh-jumper action: smart edit
# - $VAR or VAR=value: export VAR="", return to original command
# - File/dir: open in $EDITOR, return to original command
set -eo pipefail

TOKEN="$1"

# Strip quotes
TOKEN="${TOKEN#\"}"
TOKEN="${TOKEN%\"}"
TOKEN="${TOKEN#\'}"
TOKEN="${TOKEN%\'}"

# Check if it's a URL
if [[ "$TOKEN" =~ ^https?:// ]]; then
    echo "$ZJ_BUFFER"
    echo "---ZJ_PUSHLINE---"
    echo "flatpak run io.gitlab.librewolf-community \"$TOKEN\" &>/dev/null &"
    exit 4
fi

# Check if it's a Linear issue (OPS-123, DOC-456, etc.)
if [[ "$TOKEN" =~ ^(OPS|DOC|ENG|IT)-[0-9]+$ ]]; then
    echo "$ZJ_BUFFER"
    echo "---ZJ_PUSHLINE---"
    echo "flatpak run io.gitlab.librewolf-community \"https://linear.app/loft/issue/$TOKEN\" &>/dev/null &"
    exit 4
fi

# Check if it's an assignment (VAR=value)
if [[ "$TOKEN" =~ ^[A-Za-z_][A-Za-z0-9_]*=.* ]]; then
    var_name="${TOKEN%%=*}"
    value="${TOKEN#*=}"
    cursor_pos=$((7 + ${#var_name} + 2))
    echo "$ZJ_BUFFER"
    echo "---ZJ_PUSHLINE---"
    echo "export ${var_name}=\"\" # was: ${value}"
    echo "CURSOR:$cursor_pos"
    exit 3
fi

# Check if it's a variable reference ($VAR)
if [[ "$TOKEN" == \$* ]]; then
    var_name="${TOKEN#\$}"
    var_name="${var_name#\{}"
    var_name="${var_name%\}}"
    [[ -z "$var_name" ]] && exit 1
    value="${!var_name}"

    # Push original buffer, let user edit export command
    cursor_pos=$((7 + ${#var_name} + 2))  # "export " + var_name + "=\""
    echo "$ZJ_BUFFER"
    echo "---ZJ_PUSHLINE---"
    if [[ -n "$value" ]]; then
        echo "export ${var_name}=\"\" # was: ${value}"
    else
        echo "export ${var_name}=\"\""
    fi
    echo "CURSOR:$cursor_pos"
    exit 3
fi

# Expand tilde for paths
[[ "$TOKEN" == ~* ]] && TOKEN="$HOME${TOKEN#\~}"

# File or directory
if [[ -f "$TOKEN" || -d "$TOKEN" ]]; then
    echo "$ZJ_BUFFER"
    echo "---ZJ_PUSHLINE---"
    echo "\${EDITOR:-vim} \"$TOKEN\""
    exit 4
else
    echo "# Not found: $TOKEN" >&2
    exit 1
fi
