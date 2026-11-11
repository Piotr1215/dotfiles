#!/usr/bin/env bash
set -eo pipefail
reports=(inbox byrepo byproject myprojects handoffs current)
current=${TASKWARRIOR_TUI_REPORT:-}
request_file=${TASKWARRIOR_TUI_REPORT_REQUEST:-}
# Older running instances do not export the report. Their pane title may carry it.
if [[ -z "$current" && -z "$request_file" && -n "${TMUX_PANE:-}" ]]; then
  current=$(tmux display-message -p -t "$TMUX_PANE" '#{pane_title}' 2>/dev/null || true)
fi
case "$current" in inbox|byrepo|byproject|myprojects|handoffs|current) ;; *) current=inbox ;; esac
report=inbox
for i in "${!reports[@]}"; do
  if [[ "${reports[$i]}" == "$current" ]]; then report="${reports[$(((i + 1) % ${#reports[@]}))]}"; break; fi
done
version=${TASKWARRIOR_TUI_VIEW_VERSION:-0}
if [[ "$version" =~ ^[0-9]+$ ]] && ((10#$version >= 4)) && [[ -n "$request_file" && -f "$request_file" && -w "$request_file" ]]; then
  printf '%s\n' "$report" > "$request_file"
  exit
fi
# Keep the old instance paused as the parent. Retry only after the installed
# binary changes, so an old binary cannot recursively start itself.
binary=${TUI_REPORT_BINARY:-taskwarrior-tui}
binary_path=$(command -v -- "$binary") || { echo 'taskwarrior-tui binary not found' >&2; exit 1; }
fingerprint=$(sha256sum -- "$binary_path") || { echo 'Cannot fingerprint taskwarrior-tui binary' >&2; exit 1; }
fingerprint=${fingerprint%% *}
[[ "${TUI_REPORT_BRIDGE_BINARY:-}" != "$fingerprint" ]] || { echo 'Report switching requires the upgraded taskwarrior-tui binary' >&2; exit 1; }
export TUI_REPORT_BRIDGE=2 TUI_REPORT_BRIDGE_BINARY="$fingerprint"
if [[ "$report" != handoffs && -n "${TASKRC:-}" ]]; then
  legacy_rc="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../.config/taskwarrior-tui/handoffs.taskrc"
  current_rc=$(realpath -e -- "$TASKRC" 2>/dev/null || true)
  legacy_rc=$(realpath -e -- "$legacy_rc" 2>/dev/null || true)
  if [[ -n "$current_rc" && -n "$legacy_rc" && "$current_rc" == "$legacy_rc" ]]; then
    export TASKRC="$HOME/.taskrc"
  fi
fi
exec "$binary_path" -r "$report"
