#!/usr/bin/env bash
set -euo pipefail

CONF="${0%/*}/../../.tmux.conf"

rg --no-config -F \
    "bind-key '*' if-shell \"tmux list-panes -t '#{window_id}' -F '#{pane_floating_flag}' | grep -q '^1$'\"" \
    "$CONF" >/dev/null
rg --no-config -F \
    "bind-key -n M-f if-shell \"tmux list-panes -t '#{window_id}' -F '#{pane_floating_flag}' | grep -q '^1$'\"" \
    "$CONF" >/dev/null
rg --no-config -F "new-pane -c '#{pane_current_path}' -x 45% -y 80% -X 51% -Y 4 zsh" "$CONF" >/dev/null
rg --no-config -F "new-pane -c '#{pane_current_path}' -x 45% -y 80% -X 53% -Y 2 zsh" "$CONF" >/dev/null

rg --no-config -F "break-pane -W -X '#{e|-:#{@float_x},1}' -Y '#{e|-:#{@float_y},1}'" "$CONF" >/dev/null

printf 'prefix * and M-f use a right-anchored card cascade, prefix @ restores a float\n'

# Border buttons [t][z][x] draw only on floats, and [x] kills without a menu.
rg --no-config -F '#{?#{&&:#{mouse},#{pane_floating_flag}},#[align=right]#[range=control|7]' "$CONF" >/dev/null
rg --no-config -F 'bind -T root MouseDown1Control9 kill-pane -t =' "$CONF" >/dev/null
printf 'border buttons are float-only and [x] kills without confirmation\n'
