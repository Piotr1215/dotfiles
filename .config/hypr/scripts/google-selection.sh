#!/usr/bin/env bash
set -eo pipefail

# Port of GoogleSelectedText.py - search selected text
phrase=$(wl-paste -p 2>/dev/null | tr -s ' ' '+')
[[ -z "$phrase" ]] && exit 0
xdg-open "https://duckduckgo.com/?q=${phrase}"
