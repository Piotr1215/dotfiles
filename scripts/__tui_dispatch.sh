#!/usr/bin/env bash
set -eo pipefail
slot=${1:?slot required}; shift
uuid=${1:-}
root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
task_bin=${TUI_TASK_COMMAND:-task}
tmux_bin=${TUI_TMUX_COMMAND:-tmux}
report=${TASKWARRIOR_TUI_REPORT:-}
if [[ -z "$report" && -n "$uuid" ]] && "$task_bin" rc.context=none rc.hooks=off "$uuid" export | jq -e '.[0].tags // [] | index("piotr") != null' >/dev/null; then
  report=handoffs
  export TASKWARRIOR_TUI_REPORT=handoffs
fi
if [[ "$slot" == 2 ]]; then exec "$root/__cycle_tui_reports.sh" cycle; fi
if [[ "$slot" == 8 ]]; then exec "$root/__cycle_tui_reports.sh" toggle; fi
if [[ "$report" == handoffs ]]; then
  [[ -n "$uuid" ]] || { echo 'Select a handoff first' >&2; exit 1; }
  case "$slot" in
    3) exec "$root/__task_brief.sh" --popup "$uuid" ;;
    4) read -r -p 'Annotation: ' note; [[ -n "$note" ]] && exec "$task_bin" rc.context=none "$uuid" annotate "$note"; exit 0 ;;
    5) exec "$root/__tui_promote_handoff.sh" "$uuid" ;;
    6)
      [[ "$uuid" =~ ^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$ ]] || { echo 'Invalid task UUID' >&2; exit 1; }
      pane=$($tmux_bin list-panes -a -F '#{pane_id} #{@agent_name}' | awk '$2 == "triage" {print $1; exit}')
      [[ "$pane" =~ ^%[0-9]+$ ]] || { echo 'Gordon pane not found' >&2; exit 1; }
      # Validate the pane identity in the server command queue before sending.
      exec "$tmux_bin" if-shell -F -t "$pane" '#{==:#{@agent_name},triage}' "send-keys -t $pane -l -- '@${uuid:0:8} ' \; select-window -t $pane \; select-pane -t $pane" 'display-message "Gordon pane changed"' ;;
    7)
      read -r -p 'Optional completion comment: ' note
      [[ -z "$note" ]] || "$task_bin" rc.context=none "$uuid" annotate "$note"
      exec "$task_bin" rc.context=none rc.confirmation=off "$uuid" "done" ;;
  esac
fi
case "$slot" in
  1) exec "$HOME/.config/taskwarrior-tui/shortcut-scripts/taskopen-annotation.sh" "$@" ;;
  3) exec "$root/__github_issue_sync.sh" "$@" ;;
  4) exec "$HOME/.claude/scripts/__spawn_claude_directive.sh" "$@" ;;
  5) exec "$HOME/.config/taskwarrior-tui/shortcut-scripts/__toggle_claude_label.sh" "$@" ;;
  6) exec "$HOME/.config/taskwarrior-tui/shortcut-scripts/__toggle_codex_label.sh" "$@" ;;
  7) exec "$HOME/.config/taskwarrior-tui/shortcut-scripts/__annotate_with_note.sh" "$@" ;;
  9) exec "$root/__cycle_task_effort.sh" "$@" ;;
  *) echo 'Unknown shortcut' >&2; exit 2 ;;
esac
