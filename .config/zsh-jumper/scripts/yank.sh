#!/usr/bin/env bash
set -eo pipefail
TOKEN="$1"
[[ -z "$TOKEN" ]] && exit 1
printf '%s' "$TOKEN" | xsel --clipboard --input
printf '%s\n' "$ZJ_BUFFER"
