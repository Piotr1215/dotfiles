#!/usr/bin/env bash
# Opens FIRST annotation directly (no menu). Use taskopen for menu.
set -euo pipefail

annot=$(task "$1" export | jq -r '.[] | .annotations[0].description // empty')
[[ -z "$annot" ]] && exit 0

if [[ "$annot" =~ ^https?:// ]]; then
    xdg-open "$annot" 2>/dev/null &
else
    ${EDITOR:-nvim} "$annot"
fi
