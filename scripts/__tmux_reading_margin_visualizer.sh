#!/usr/bin/env bash
# Run a music visualizer under the time-off reading margin's picker.
# It ends itself once the margin pane is gone, so nothing has to close it.

set -eo pipefail

margin_pane="${1:-}"
if [[ -z "$margin_pane" ]]; then
  printf 'usage: %s margin-pane-id\n' "${0##*/}" >&2
  exit 1
fi
visualizer="${TMUX_READING_MARGIN_VISUALIZER-cava}"

# Poll until the margin pane or the visualizer is gone, then stop the
# visualizer. display-message prints nothing for a missing pane, so compare
# its output rather than its exit status.
watch_margin() {
  local pid="$1"
  while kill -0 "$pid" 2>/dev/null &&
    [[ "$(tmux display-message -p -t "$margin_pane" '#{pane_id}' 2>/dev/null)" == "$margin_pane" ]]; do
    sleep 0.5
  done
  kill -TERM "$pid" 2>/dev/null || true
}

# exec keeps this shell's pid, so $$ is the visualizer's pid once it starts.
watch_margin "$$" &
exec "$visualizer"
