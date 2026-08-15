#!/usr/bin/env bash
set -euo pipefail

CONF="${0%/*}/../../.tmux.conf"

rg --no-config -F \
    "bind-key '*' if-shell \"tmux list-panes -t '#{window_id}' -F '#{pane_floating_flag}' | grep -q '^1$'\"" \
    "$CONF" >/dev/null
rg --no-config -F \
    "bind-key -n M-f if-shell \"tmux list-panes -t '#{window_id}' -F '#{pane_floating_flag}' | grep -q '^1$'\"" \
    "$CONF" >/dev/null
rg --no-config -F "new-pane -c '#{pane_current_path}' -x 117 -y 36 -X 172 -Y 4 zsh" "$CONF" >/dev/null
rg --no-config -F "new-pane -c '#{pane_current_path}' -x 117 -y 36 -X 176 -Y 2 zsh" "$CONF" >/dev/null

printf 'prefix * and M-f use a right-anchored card cascade\n'
