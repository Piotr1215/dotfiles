#!/usr/bin/env bash
# Show handoffs and the live agent roster in the work margin.

set -eo pipefail

if [[ "${1:-}" != "--render" && "${1:-}" != "--cached-render" && "${1:-}" != "--raw-render" ]]; then
  session="${1:-$(tmux display-message -p '#{session_name}')}"
  window="${2:-$(tmux display-message -p '#{window_id}')}"
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  exec python3 "$script_dir/__tmux_reading_margin_view.py" \
    "$0" --raw-render "$session" "$window"
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
if [[ "$mode" == --raw-render ]]; then
  # Retain logical lines so a resize can reflow immediately while the next
  # live roster is being collected.
  width=10000
  export COCKPIT_RAW=1
  export COCKPIT_ORDER_FILE="${CYCLE_AGENT_CACHE_DIR:-${XDG_RUNTIME_DIR:-/tmp}/cycle-agent-order}/order"
fi

cockpit_command="${TMUX_READING_MARGIN_COCKPIT_STATE_COMMAND:-$HOME/.claude/scripts/__cockpit_state.sh}"
focus_command="${TMUX_READING_MARGIN_FOCUS_COMMAND:-$HOME/.claude/scripts/__focus.py}"

# Handoffs come first and scroll with the roster. Ranking happens outside the
# pane; only this independent handoff block retains its short cache.
if [[ "$mode" == --cached-render || "$mode" == --raw-render ]]; then
  cache_root="${XDG_RUNTIME_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}}/reading-margin"
  (umask 077; mkdir -p "$cache_root")
  key=$(printf '%s\0%s' "${TMUX:-}" "${TMUX_PANE:-}" | sha256sum)
  cache="$cache_root/${key%% *}"
fi

if [[ -x "$focus_command" ]]; then
  if [[ "$mode" == --cached-render || "$mode" == --raw-render ]]; then
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
