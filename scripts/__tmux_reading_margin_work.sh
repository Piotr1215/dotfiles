#!/usr/bin/env bash
# Show the live vertical cockpit, then Piotr's open asks, in the work margin.

set -eo pipefail

if [[ "${1:-}" != "--render" ]]; then
  session="${1:-$(tmux display-message -p '#{session_name}')}"
  window="${2:-$(tmux display-message -p '#{window_id}')}"
  viddy="${TMUX_READING_MARGIN_VIDDY_COMMAND:-viddy}"
  exec "$viddy" --interval 15 --differences --no-title \
    "$0" --render "$session" "$window"
fi

session="${2:-}"
window="${3:-}"
if [[ -z "$session" || -z "$window" ]]; then
  printf 'usage: %s [session window] | --render session window\n' "${0##*/}" >&2
  exit 2
fi

width="${COLUMNS:-}"
if [[ -n "${TMUX_PANE:-}" ]]; then
  width="$(tmux display-message -p -t "$TMUX_PANE" '#{pane_width}' 2>/dev/null || true)"
fi
case "$width" in ''|*[!0-9]*) width=100 ;; esac

cockpit_command="${TMUX_READING_MARGIN_COCKPIT_STATE_COMMAND:-$HOME/.claude/scripts/__cockpit_state.sh}"
asks_command="${TMUX_READING_MARGIN_ASKS_COMMAND:-$HOME/.claude/scripts/__piotr_asks_margin.sh}"

COCKPIT_LAYOUT=vertical COCKPIT_VERTICAL_WIDTH="$width" "$cockpit_command"

# Piotr's open asks last, below the live cockpit. Deliberately the bottom
# section: the cockpit answers "what is running now" and is read constantly,
# while the asks list answers "what is waiting on me" and is read on a glance
# down. It prints nothing when there are no asks, so the margin does not grow a
# permanently empty heading.
asks_width="$width"
if [[ -x "$asks_command" ]]; then
  printf '\n'
  TMUX_PIOTR_ASKS_WIDTH="$asks_width" "$asks_command" || true
fi
