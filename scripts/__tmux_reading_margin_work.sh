#!/usr/bin/env bash
# Show Piotr's Top Three Focus, then the live vertical cockpit, in the work margin.

set -eo pipefail

if [[ "${1:-}" != "--render" && "${1:-}" != "--cached-render" ]]; then
  session="${1:-$(tmux display-message -p '#{session_name}')}"
  window="${2:-$(tmux display-message -p '#{window_id}')}"
  viddy="${TMUX_READING_MARGIN_VIDDY_COMMAND:-viddy}"
  # Viddy redraws its old snapshot on SIGWINCH but only re-runs the command at
  # its interval. Check twice a second so a new pane width reaches the renderer.
  exec "$viddy" --interval 0.5 --no-title \
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
if (( width < 20 )); then
  placeholder='pane too narrow'
  printf '%s\n' "${placeholder:0:width}"
  exit 0
fi

cockpit_command="${TMUX_READING_MARGIN_COCKPIT_STATE_COMMAND:-$HOME/.claude/scripts/__cockpit_state.sh}"
focus_command="${TMUX_READING_MARGIN_FOCUS_COMMAND:-$HOME/.claude/scripts/__focus.py}"

# Focus first. It is a fixed eleven-line block (three spaced items and the
# handoff line), so it stays above the fold and never needs scrolling, while the
# cockpit below can run long. The block only reads its cache and the ledger;
# ranking happens in systemd, never here.
if [[ -x "$focus_command" ]]; then
  "$focus_command" render --width "$width" || true
  printf '\n'
fi

if [[ "$mode" == --cached-render ]]; then
  # Collect the expensive tmux and TaskWarrior state in the background. Keep
  # an unwrapped snapshot so a resize only needs a fast reflow of that data.
  cache_root="${XDG_RUNTIME_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}}/reading-margin"
  (umask 077; mkdir -p "$cache_root")
  key=$(printf '%s\0%s' "${TMUX:-}" "${TMUX_PANE:-}" | sha256sum)
  cache="$cache_root/${key%% *}"
  if [[ -z $(find "$cache" -mmin -0.0833 2>/dev/null) ]]; then
    (
      flock -n 9 || exit 0
      if [[ -z $(find "$cache" -mmin -0.0833 2>/dev/null) ]]; then
        temp="$cache.$BASHPID"
        if COCKPIT_LAYOUT=vertical COCKPIT_VERTICAL_WIDTH=10000 "$cockpit_command" >"$temp"; then
          mv -f "$temp" "$cache"
        fi
      fi
    ) 9>"$cache.lock" </dev/null >/dev/null 2>&1 &
  fi
  if [[ -f "$cache" ]]; then
    python3 "$HOME/.claude/scripts/__cockpit_wrap.py" --board "$width" < "$cache"
  else
    printf 'Loading cockpit\n'
  fi
else
  COCKPIT_LAYOUT=vertical COCKPIT_VERTICAL_WIDTH="$width" "$cockpit_command"
fi
