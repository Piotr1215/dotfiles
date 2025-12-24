#!/usr/bin/env bash
# Copy stdin to clipboard - works over SSH (OSC 52) and locally (xsel)
# Usage: echo "text" | __clipboard_copy.sh
#    or: __clipboard_copy.sh "text"

set -eo pipefail

if [[ $# -gt 0 ]]; then
    data="$*"
else
    data=$(cat)
fi

if [[ -n "$SSH_CONNECTION" ]]; then
    encoded=$(printf '%s' "$data" | base64 | tr -d '\n')
    if [[ -n "$TMUX" ]]; then
        printf '\033Ptmux;\033\033]52;c;%s\a\033\\' "$encoded"
    else
        printf '\033]52;c;%s\a' "$encoded"
    fi
else
    printf '%s' "$data" | DISPLAY=:0 xsel --clipboard
fi
