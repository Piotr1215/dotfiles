#!/usr/bin/env bash
# Show the live agent roster in the work margin.

set -eo pipefail

if [[ "${1:-}" != "--render" && "${1:-}" != "--cached-render" && "${1:-}" != "--raw-render" ]]; then
  session="${1:-$(tmux display-message -p '#{session_name}')}"
  window="${2:-$(tmux display-message -p '#{window_id}')}"
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  state_dir="$(python3 "$script_dir/__tmux_reading_margin_view.py" --state-dir)"
  (umask 077; mkdir -p "$state_dir")
  exec {setup_fd}>"$state_dir/setup.lock"
  flock "$setup_fd"
  if [[ -z ${TMUX_READING_MARGIN_COLLECT_COMMAND:-} ]]; then
    collector_source="$script_dir/tmux_reading_margin_collect.go"
    read -r collector_hash _ < <(sha256sum "$collector_source")
    collector="$state_dir/collector-$collector_hash"
    if [[ ! -x "$collector" ]]; then
      go build -trimpath -o "$collector.$BASHPID.tmp" "$collector_source"
      mv -f "$collector.$BASHPID.tmp" "$collector"
    fi
    export TMUX_READING_MARGIN_COLLECT_COMMAND="$collector"
  fi
  # Keep the existing hook arrays. Each server installs this invalidation path
  # once; viewer redraws and scrolling never collect data or start processes.
  hook_marker="v1:$state_dir"
  if [[ $(tmux show-options -gqv @reading_margin_shared_hooks) != "$hook_marker" ]]; then
    printf -v touch_command 'touch -- %q' "$state_dir/dirty"
    printf -v hook_command 'run-shell -b %q' "$touch_command"
    for hook in after-set-option after-set-environment session-created session-closed \
      session-renamed window-linked window-unlinked pane-created pane-exited; do
      tmux set-hook -ag "$hook" "$hook_command"
    done
    tmux set-option -g @reading_margin_shared_hooks "$hook_marker"
  fi
  # Selection never recollects the roster or waits for a shell. Resolve the
  # current pane in the background, so bursts of switches converge on live state.
  if [[ $(tmux show-options -gqv @reading_margin_focus_hooks) != "$hook_marker" ]]; then
    printf -v active_command 'tmux display-message -p -t "#{hook_window}" '\''##{pane_id}'\'' > %q/active-#{hook_window}' "$state_dir"
    printf -v active_hook 'run-shell -b %q' "$active_command"
    tmux set-hook -ag window-pane-changed "$active_hook"
    tmux set-option -g @reading_margin_focus_hooks "$hook_marker"
  fi
  export TMUX_READING_MARGIN_WINDOW="$window"
  exec {setup_fd}>&-
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
  # Keep full logical lines so widening reveals clipped data immediately.
  width=10000
  export COCKPIT_RAW=1
  export COCKPIT_ORDER_FILE="${COCKPIT_ORDER_FILE:-${CYCLE_AGENT_CACHE_DIR:-${XDG_RUNTIME_DIR:-/tmp}/cycle-agent-order}/order}"
fi

cockpit_command="${TMUX_READING_MARGIN_COCKPIT_STATE_COMMAND:-$HOME/.claude/scripts/__cockpit_state.sh}"

# The one shared collector owns caching and invalidation. Its input reads must
# stay fresh; viewers reuse the resulting frame for resize and scrolling.
COCKPIT_CACHE=0 COCKPIT_LAYOUT=vertical COCKPIT_VERTICAL_WIDTH="$width" "$cockpit_command"
