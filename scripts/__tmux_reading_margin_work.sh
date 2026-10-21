#!/usr/bin/env bash
# Show Piotr's Top Three Focus, then the live vertical cockpit, in the work margin.

set -eo pipefail

if [[ "${1:-}" != "--render" ]]; then
  session="${1:-$(tmux display-message -p '#{session_name}')}"
  window="${2:-$(tmux display-message -p '#{window_id}')}"
  viddy="${TMUX_READING_MARGIN_VIDDY_COMMAND:-viddy}"
  exec "$viddy" --interval 5 --no-title \
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
focus_command="${TMUX_READING_MARGIN_FOCUS_COMMAND:-$HOME/.claude/scripts/__focus.py}"

# Focus first. It is a fixed eight-line block (three items and the handoff
# line), so it stays above the fold and never needs scrolling, while the
# cockpit below can run long. The block only reads its cache and the ledger;
# ranking happens in systemd, never here.
if [[ -x "$focus_command" ]]; then
  "$focus_command" render --width "$width" || true
  printf '\n'
fi

COCKPIT_LAYOUT=vertical COCKPIT_VERTICAL_WIDTH="$width" "$cockpit_command"
