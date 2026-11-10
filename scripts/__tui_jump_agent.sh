#!/usr/bin/env bash
# Key 0 in taskwarrior-tui: switch tmux to the agent working on the selected task.
# Spawns record their session as a "tmux session <name>" annotation; a task can
# carry several (retries, follow-ups), so the newest live one wins. Inside that
# session the pane tagged @agent_name is the agent, which is not always the
# active pane, so it is preferred over the session's current pane.
set -eo pipefail

uuid=${1:-}
task_bin=${TUI_TASK_COMMAND:-task}
tmux_bin=${TUI_TMUX_COMMAND:-tmux}

[[ -n "$uuid" ]] || { echo 'Select a task first' >&2; exit 1; }

# Session names from the task's annotations, newest annotation first.
mapfile -t sessions < <("$task_bin" rc.context=none rc.hooks=off "$uuid" export 2>/dev/null | jq -r '
  .[0].annotations // [] | sort_by(.entry) | reverse | .[].description
  | capture("tmux session (?<s>[A-Za-z0-9._-]+)") | .s' 2>/dev/null || true)
[[ ${#sessions[@]} -gt 0 ]] || { echo 'No agent session recorded on this task' >&2; exit 1; }

# Return the agent pane in a live session: the pane tagged with the session's
# own name, else any tagged pane, else the session itself.
agent_target() {
  local session=$1 pane tag tagged=""
  while read -r pane tag; do
    [[ -n "$tag" ]] || continue
    if [[ "$tag" == "$session" ]]; then printf '%s\n' "$pane"; return; fi
    [[ -n "$tagged" ]] || tagged=$pane
  done < <("$tmux_bin" list-panes -s -t "=$session" -F '#{pane_id} #{@agent_name}' 2>/dev/null)
  printf '%s\n' "${tagged:-=$session:}"
}

live=""
for session in "${sessions[@]}"; do
  if "$tmux_bin" has-session -t "=$session" 2>/dev/null; then live=$session; break; fi
done
[[ -n "$live" ]] || { echo "No live agent session (recorded: ${sessions[*]})" >&2; exit 1; }
exec "$tmux_bin" switch-client -t "$(agent_target "$live")"
