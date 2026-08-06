#!/usr/bin/env bash

set -euo pipefail

ensure=false
if [ "${1:-}" = --ensure-session ]; then
  session_name="${2:-}"
  if [[ -z "$session_name" ]]; then
    printf 'usage: %s --ensure-session session-name\n' "${0##*/}" >&2
    exit 2
  fi
  [[ "$session_name" =~ _[0-9a-f]{4}$ ]] && exit 0
  target_pane="$(tmux display-message -p -t "$session_name" '#{pane_id}' 2>/dev/null || true)"
  [ -n "$target_pane" ] || exit 0
  ensure=true
else
  target_pane="${1:-${TMUX_PANE:-}}"
fi
if [[ -z "$target_pane" ]]; then
  printf 'usage: %s pane-id | --ensure-session session-name\n' "${0##*/}" >&2
  exit 2
fi

window_id="$(tmux display-message -p -t "$target_pane" '#{window_id}')"
margin_pane="$(tmux show-options -wqv -t "$window_id" @reading_margin_pane)"

if [[ -n "$margin_pane" ]] &&
  [[ "$(tmux display-message -p -t "$margin_pane" '#{window_id}' 2>/dev/null || true)" == "$window_id" ]]; then
  $ensure && exit 0
  tmux kill-pane -t "$margin_pane"
  tmux set-option -wu -t "$window_id" @reading_margin_pane
  exit 0
fi

tmux set-option -wu -t "$window_id" @reading_margin_pane 2>/dev/null || true
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
timeoff_file="${TMUX_READING_MARGIN_TIMEOFF_FILE:-/tmp/timeoff_mode}"
if [ -f "$timeoff_file" ]; then
  margin_command="${TMUX_READING_MARGIN_WEEKEND_COMMAND:-exec \"$script_dir/__play_track.sh\" --run}"
  input_flag=-e
else
  margin_command="${TMUX_READING_MARGIN_WORK_COMMAND:-exec \"$HOME/.claude/scripts/__cockpit_board.sh\" --vertical}"
  input_flag=-d
fi
margin_pane="$(
  tmux split-window -bdfl 33% -h -t "$target_pane" -P -F '#{pane_id}' "$margin_command"
)"
tmux set-option -w -t "$window_id" @reading_margin_pane "$margin_pane"
tmux select-pane "$input_flag" -T ' ' -t "$margin_pane"
tmux select-pane -t "$target_pane"
