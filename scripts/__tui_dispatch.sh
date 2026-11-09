#!/usr/bin/env bash
set -eo pipefail
slot=${1:?slot required}; shift
uuid=${1:-}
root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
task_bin=${TUI_TASK_COMMAND:-task}
tmux_bin=${TUI_TMUX_COMMAND:-tmux}
if [[ "$slot" == 1 ]]; then exec "$HOME/.config/taskwarrior-tui/shortcut-scripts/taskopen-annotation.sh" "$@"; fi
# Key 2 cycles views in every report, so it runs before the handoff lookup.
if [[ "$slot" == 2 ]]; then exec "$root/__cycle_tui_reports.sh"; fi
report=${TASKWARRIOR_TUI_REPORT:-}
if [[ -z "$report" && -n "$uuid" ]] && "$task_bin" rc.context=none rc.hooks=off "$uuid" export | jq -e '.[0].tags // [] | index("piotr") != null' >/dev/null; then
  report=handoffs
  export TASKWARRIOR_TUI_REPORT=handoffs
fi
if [[ "$report" == handoffs ]]; then
  [[ -n "$uuid" ]] || { echo 'Select a handoff first' >&2; exit 1; }
  case "$slot" in
    3) exec "$root/__task_brief.sh" --popup "$uuid" ;;
    4) read -r -p 'Annotation: ' note; [[ -n "$note" ]] && exec "$task_bin" rc.context=none "$uuid" annotate "$note"; exit 0 ;;
    5) exec "$root/__tui_promote_handoff.sh" "$uuid" ;;
    6) exec "$root/__tui_ack_handoff.sh" "$uuid" ;;
    7|9)
      [[ "$uuid" =~ ^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$ ]] || { echo 'Invalid task UUID' >&2; exit 1; }
      task_json=$("$task_bin" rc.context=none rc.hooks=off "$uuid" export)
      # shellcheck disable=SC1091
      source "$root/__lib_tui_packet.sh"
      token=$(tui_task_packet "$uuid" '-' <<< "$task_json") || { echo 'Task not found' >&2; exit 1; }
      payload="$token"
      [[ "$slot" != 7 ]] || payload="/ops-spawn-agent $token "
      [[ "$slot" != 9 ]] || payload="$token update my brief with more information about this action, why it is needed now, and what I need to do. Check the source and put explanations and any open questions in my brief document. Use Markdown paragraphs, lists, links and backticks. "
      pane=$($tmux_bin list-panes -a -F '#{pane_id} #{@agent_name}' | awk '$2 == "triage" {print $1; exit}')
      [[ "$pane" =~ ^%[0-9]+$ ]] || { echo 'Gordon pane not found' >&2; exit 1; }
      # A named buffer carries arbitrary task text without parsing it as tmux commands.
      # The identity guard, paste, and focus run together in tmux's command queue.
      buffer="tui-handoff-$$-$RANDOM"
      timestamp=$(date +%s)
      exec "$tmux_bin" set-buffer -b "$buffer" -- "$payload" \; \
        if-shell -F -t "$pane" '#{==:#{@agent_name},triage}' \
        "set-option -p -t $pane @agent_injected_at $timestamp ; paste-buffer -d -p -b $buffer -t $pane ; switch-client -t $pane" \
        "delete-buffer -b $buffer ; display-message 'Gordon pane changed'" ;;
    8) echo "No action assigned for handoffs on key $slot" >&2; exit 0 ;;
  esac
fi
case "$slot" in
  0) exec "$HOME/.config/taskwarrior-tui/shortcut-scripts/__annotate_with_note.sh" "$@" ;;
  3) exec "$root/__github_issue_sync.sh" "$@" ;;
  4) exec "$HOME/.claude/scripts/__spawn_claude_directive.sh" "$@" ;;
  5) exec "$HOME/.config/taskwarrior-tui/shortcut-scripts/__toggle_claude_label.sh" "$@" ;;
  6) exec "$HOME/.config/taskwarrior-tui/shortcut-scripts/__toggle_codex_label.sh" "$@" ;;
  7) exec "$root/__toggle_linear_backlog.sh" "$@" ;;
  8) exec "$root/__create_linear_issue.sh" "$@" ;;
  9) exec "$root/__cycle_task_effort.sh" "$@" ;;
  *) echo 'Unknown shortcut' >&2; exit 2 ;;
esac
