#!/usr/bin/env bash
set -eo pipefail

accounts=$(ykman oath accounts list 2>/dev/null || true)
count=0
[[ -n "$accounts" ]] && count=$(echo "$accounts" | wc -l)

tooltip=""
if [[ -n "$accounts" ]]; then
	tooltip=$(echo "$accounts" | tr '\n' '\\' | sed 's/\\/\\n/g')
fi

if ((count == 0)); then
	printf '{"text": "", "class": "empty"}\n'
else
	printf '{"text": "🔑%d", "tooltip": "%s"}\n' "$count" "$tooltip"
fi
