#!/usr/bin/env bash

set -euo pipefail

ensure=false
repair=false
status=false
case "${1:-}" in
--ensure-session)
  session_name="${2:-}"
  if [[ -z "$session_name" ]]; then
    printf 'usage: %s --ensure-session session-name\n' "${0##*/}" >&2
    exit 2
  fi
  [[ "$session_name" =~ _[0-9a-f]{4}$ ]] && exit 0
  target_pane="$(tmux display-message -p -t "$session_name" '#{pane_id}' 2>/dev/null || true)"
  [ -n "$target_pane" ] || exit 0
  ensure=true
  ;;
--repair-window)
  window_id="${2:-}"
  if [[ -z "$window_id" ]]; then
    printf 'usage: %s --repair-window window-id\n' "${0##*/}" >&2
    exit 2
  fi
  window_id="$(tmux display-message -p -t "$window_id" '#{window_id}' 2>/dev/null || true)"
  [ -n "$window_id" ] || exit 0
  repair=true
  ;;
--status)
  target_pane="${2:-${TMUX_PANE:-}}"
  if [[ -z "$target_pane" ]]; then
    target_pane="$(tmux display-message -p '#{pane_id}' 2>/dev/null || true)"
  fi
  status=true
  ;;
*)
  target_pane="${1:-${TMUX_PANE:-}}"
  ;;
esac
if ! $repair && [[ -z "$target_pane" ]]; then
  printf 'usage: %s pane-id | --ensure-session session-name\n' "${0##*/}" >&2
  exit 2
fi

if ! $repair; then
  window_id="$(tmux display-message -p -t "$target_pane" '#{window_id}')"
fi
margin_pane="$(tmux show-options -wqv -t "$window_id" @reading_margin_pane)"
margin_exists=false
if [[ -n "$margin_pane" ]] &&
  [[ "$(tmux display-message -p -t "$margin_pane" '#{window_id}' 2>/dev/null || true)" == "$window_id" ]]; then
  margin_exists=true
fi

set_visible() {
  tmux set-option -w -t "$window_id" @reading_margin_visible "$1"
}

repair_width() {
  local expected_width margin_width window_width
  window_width="$(tmux display-message -p -t "$window_id" '#{window_width}')"
  margin_width="$(tmux display-message -p -t "$margin_pane" '#{pane_width}')"
  expected_width=$((window_width * 33 / 100))
  ((expected_width > 0)) || expected_width=1
  if ((margin_width != expected_width)); then
    tmux resize-pane -t "$margin_pane" -x 33%
  fi
}

if $status; then
  default="$(tmux show-options -gqv @reading_margin_default)"
  $margin_exists && visible=on || visible=off
  printf 'reading-margin default=%s visible=%s window=%s' "${default:-off}" "$visible" "$window_id"
  if $margin_exists; then
    printf ' pane=%s width=%s\n' "$margin_pane" \
      "$(tmux display-message -p -t "$margin_pane" '#{pane_width}')"
  else
    printf '\n'
  fi
  exit 0
fi

if $repair; then
  if $margin_exists; then
    set_visible on
    repair_width
  else
    tmux set-option -wu -t "$window_id" @reading_margin_pane 2>/dev/null || true
    set_visible off
  fi
  exit 0
fi

if $margin_exists; then
  if $ensure; then
    set_visible on
    repair_width
    exit 0
  fi
  set_visible off
  tmux kill-pane -t "$margin_pane"
  tmux set-option -wu -t "$window_id" @reading_margin_pane
  exit 0
fi

tmux set-option -wu -t "$window_id" @reading_margin_pane 2>/dev/null || true
if $ensure && [[ "$(tmux show-options -gqv @reading_margin_default)" != on ]]; then
  set_visible off
  exit 0
fi
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
timeoff_file="${TMUX_READING_MARGIN_TIMEOFF_FILE:-/tmp/timeoff_mode}"
if [ -f "$timeoff_file" ]; then
  margin_command="${TMUX_READING_MARGIN_WEEKEND_COMMAND:-exec \"$script_dir/__play_track.sh\" --run}"
  input_flag=-e
else
  session_name="$(tmux display-message -p -t "$target_pane" '#{session_name}')"
  margin_command="${TMUX_READING_MARGIN_WORK_COMMAND:-exec \"$script_dir/__tmux_reading_margin_work.sh\" \"$session_name\" \"$window_id\"}"
  input_flag=-d
fi
margin_pane="$(
  tmux split-window -bdfl 33% -h -t "$target_pane" -P -F '#{pane_id}' "$margin_command"
)"
tmux set-option -w -t "$window_id" @reading_margin_pane "$margin_pane"
set_visible on
tmux select-pane "$input_flag" -T ' ' -t "$margin_pane"
tmux select-pane -t "$target_pane"
