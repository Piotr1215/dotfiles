#!/usr/bin/env bash
set -eo pipefail
TOKEN="$1"
[[ -z "$TOKEN" ]] && exit 1
echo -n "$TOKEN" | xclip -selection clipboard
echo "$ZJ_BUFFER"
