#!/usr/bin/env bash
set -eo pipefail
reports=(inbox byrepo byproject current)
current="${TASKWARRIOR_TUI_REPORT:-inbox}"
state_file="${TUI_REPORT_STATE_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/taskwarrior-tui/previous-report-${TMUX_PANE:-default}}"
request_file=${TASKWARRIOR_TUI_REPORT_REQUEST:-}
[[ -n "$request_file" && -f "$request_file" && -w "$request_file" ]] || { echo "Report switching requires an upgraded taskwarrior-tui" >&2; exit 1; }
if [[ "${1:-cycle}" == toggle ]]; then
  if [[ "$current" == handoffs ]]; then
    report=$(cat "$state_file" 2>/dev/null || printf inbox)
    [[ "$report" =~ ^[a-zA-Z0-9_-]+$ && "$report" != handoffs ]] || report=inbox
  else
    mkdir -p "$(dirname "$state_file")"
    printf '%s\n' "$current" > "$state_file"
    report=handoffs
  fi
else
  report=inbox
  for i in "${!reports[@]}"; do
    if [[ "${reports[$i]}" == "$current" ]]; then report="${reports[$(((i + 1) % ${#reports[@]}))]}"; break; fi
  done
fi
printf '%s\n' "$report" > "$request_file"
