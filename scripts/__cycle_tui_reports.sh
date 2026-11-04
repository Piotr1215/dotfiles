#!/usr/bin/env bash
set -eo pipefail
reports=(inbox byrepo byproject handoffs current)
current="${TASKWARRIOR_TUI_REPORT:-inbox}"
request_file=${TASKWARRIOR_TUI_REPORT_REQUEST:-}
[[ -n "$request_file" && -f "$request_file" && -w "$request_file" ]] || { echo 'Report switching requires an upgraded taskwarrior-tui' >&2; exit 1; }
report=inbox
for i in "${!reports[@]}"; do
  if [[ "${reports[$i]}" == "$current" ]]; then report="${reports[$(((i + 1) % ${#reports[@]}))]}"; break; fi
done
printf '%s\n' "$report" > "$request_file"
