#!/usr/bin/env bash
set -eo pipefail

uuid=${1:-}
[[ "$uuid" =~ ^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$ ]] || { echo 'A full task UUID is required' >&2; exit 1; }
task_bin=${TUI_TASK_COMMAND:-task}
tmux_bin=${TUI_TMUX_COMMAND:-tmux}
root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$root/__lib_tui_packet.sh"
task_json=$("$task_bin" rc.context=none rc.hooks=off "$uuid" export) || { echo 'Task export failed' >&2; exit 1; }
token=$(tui_task_packet "$uuid" no-repo <<< "$task_json") || { echo 'Task not found or UUID does not match' >&2; exit 1; }
pane=$("$tmux_bin" list-panes -a -F '#{pane_id} #{@agent_name}' | awk '$2 == "triage" {print $1; exit}') || { echo 'Could not find Gordon pane' >&2; exit 1; }
[[ "$pane" =~ ^%[0-9]+$ ]] || { echo 'Gordon pane not found' >&2; exit 1; }
"$tmux_bin" send-keys -t "$pane" -l -- "$token "
exec "$tmux_bin" switch-client -t "$pane"
