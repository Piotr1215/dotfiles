#!/usr/bin/env bash
# Hide selected tasks until a future Taskwarrior wait date.
set -eo pipefail

mode=popup
if [[ "${1:-}" == --defer ]]; then mode=defer; shift; fi
[[ $# -gt 0 ]] || { echo 'Select a task first.' >&2; exit 1; }
for uuid in "$@"; do
  [[ "$uuid" =~ ^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$ ]] || {
  echo 'Select tasks with full task UUIDs.' >&2
  exit 1
  }
done

input_bin=$(command -v "${TUI_INPUT_COMMAND:-gum}") || {
  echo 'gum is required for the wait-date dialog.' >&2
  exit 127
}
task_bin=$(command -v "${TUI_TASK_COMMAND:-task}") || {
  echo 'task is required to defer tasks.' >&2
  exit 127
}

if [[ "$mode" == popup ]]; then
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/${0##*/}"
  printf -v popup_command '%q ' "$self" --defer "$@"
  exec "${TUI_TMUX_COMMAND:-tmux}" display-popup -EE -h 10 -w 80% \
    -T ' Show tasks later ' \
    -e "TUI_INPUT_COMMAND=$input_bin" \
    -e "TUI_TASK_COMMAND=$task_bin" \
    "$popup_command"
fi

if when=$("$input_bin" input --char-limit 0 --prompt 'Show again: ' \
  --value tomorrow --placeholder 'tomorrow, monday, or YYYY-MM-DD' \
  --header 'Hide selected tasks until this date. They stay open. Esc cancels.'); then
  [[ "$when" =~ [^[:space:]] ]] || exit 0
else
  status=$?
  [[ "$status" == 1 || "$status" == 130 ]] && exit 0
  exit "$status"
fi

future=$("$task_bin" rc.context=none rc.hooks=off calc "$when > now") || {
  echo 'Choose a future date, such as tomorrow, monday, or now+1h.' >&2
  exit 1
}
[[ "$future" == true ]] || {
  echo 'Choose a future date, such as tomorrow, monday, or now+1h.' >&2
  exit 1
}

for uuid in "$@"; do
  "$task_bin" rc.context=none rc.confirmation=off "$uuid" modify "wait:$when"
done
