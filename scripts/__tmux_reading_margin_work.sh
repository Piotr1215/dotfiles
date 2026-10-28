#!/usr/bin/env bash
# Show Piotr's Top Three Focus, then the live vertical cockpit, in the work margin.

set -eo pipefail

if [[ "${1:-}" != "--render" && "${1:-}" != "--cached-render" ]]; then
  session="${1:-$(tmux display-message -p '#{session_name}')}"
  window="${2:-$(tmux display-message -p '#{window_id}')}"
  viddy="${TMUX_READING_MARGIN_VIDDY_COMMAND:-viddy}"
  # Viddy re-runs the renderer at its shortest interval so every completed
  # draw uses the current pane width and live roster.
  exec "$viddy" --interval 0.1 --no-title \
    "$0" --cached-render "$session" "$window"
fi

mode="$1"
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

# Focus first. It is a fixed eleven-line block (three spaced items and the
# handoff line), so it stays above the fold and never needs scrolling, while the
# cockpit below can run long. The block only reads its cache and the ledger;
# ranking happens in systemd, never here.
if [[ "$mode" == --cached-render ]]; then
  cache_root="${XDG_RUNTIME_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}}/reading-margin"
  (umask 077; mkdir -p "$cache_root")
  key=$(printf '%s\0%s' "${TMUX:-}" "${TMUX_PANE:-}" | sha256sum)
  cache="$cache_root/${key%% *}"
fi

if [[ -x "$focus_command" ]]; then
  if [[ "$mode" == --cached-render ]]; then
    focus_cache="$cache.focus-$width"
    if [[ -z $(find "$focus_cache" -mmin -0.0833 2>/dev/null) ]]; then
      focus_tmp="$focus_cache.$BASHPID"
      if "$focus_command" render --width "$width" >"$focus_tmp"; then
        mv -f "$focus_tmp" "$focus_cache"
      fi
    fi
    [[ -f "$focus_cache" ]] && cat "$focus_cache"
  else
    "$focus_command" render --width "$width" || true
  fi
  printf '\n'
fi

# Roster rows come from live tmux panes on every draw. Caching this board here
# or in the cockpit can keep a closed agent visible or hide a new one. Only
# Focus above is cached; a cold draw and a resize both render synchronously.
COCKPIT_CACHE=0 COCKPIT_LAYOUT=vertical COCKPIT_VERTICAL_WIDTH="$width" "$cockpit_command"
