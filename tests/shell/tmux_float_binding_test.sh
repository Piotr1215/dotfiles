#!/usr/bin/env bash
set -euo pipefail

CONF="${0%/*}/../../.tmux.conf"

rg --no-config -F \
    "bind-key '*' if-shell \"tmux list-panes -t '#{window_id}' -F '#{pane_floating_flag}' | grep -q '^1$'\"" \
    "$CONF" >/dev/null
rg --no-config -F \
    "bind-key -n M-f if-shell \"tmux list-panes -t '#{window_id}' -F '#{pane_floating_flag}' | grep -q '^1$'\"" \
    "$CONF" >/dev/null
rg --no-config -F "new-pane -c '#{pane_current_path}' -x 50% -y 50% -X 48% -Y 2 zsh" "$CONF" >/dev/null
rg --no-config -F "new-pane -c '#{pane_current_path}' -x 50% -y 50% zsh ; move-pane -P top-right" "$CONF" >/dev/null

rg --no-config -F "break-pane -W -X '#{e|-:#{@float_x},1}' -Y '#{e|-:#{@float_y},1}'" "$CONF" >/dev/null

printf 'prefix * and M-f open a quarter float top-right with a card cascade, prefix @ restores a float\n'

# On a real tmux 3.8 server, run the M-f binding twice in a 255x61 window (odd
# width, where -X 50% alone lands a column short): the first float is a quarter
# of the window in exactly the top-right snap cell, the second cascades.
if tmux -L "float-bind-probe-$$" -f /dev/null new-session -d -s p -x 80 -y 24 \; new-pane -x 20 -y 8 2>/dev/null; then
    tmux -L "float-bind-probe-$$" kill-server
    sock="float-bind-$$"
    tmp=$(mktemp)
    rg --no-config -A2 '^bind-key -n M-f ' "$CONF" > "$tmp"
    tmux -L "$sock" -f /dev/null new-session -d -s t -x 255 -y 61
    tmux -L "$sock" source-file "$tmp"
    body=$(tmux -L "$sock" list-keys -T root M-f | sed -E 's/^bind-key +-T root +M-f +//')
    tmux -L "$sock" source-file - <<<"$body"
    first=$(tmux -L "$sock" list-panes -t t -F '#{pane_floating_flag} #{pane_left} #{pane_top} #{pane_width} #{pane_height}' | awk '$1==1')
    tmux -L "$sock" source-file - <<<"$body"
    floats=$(tmux -L "$sock" list-panes -t t -F '#{pane_floating_flag}' | grep -c '^1$')
    tmux -L "$sock" kill-server
    rm -f "$tmp"
    [ "$first" = "1 129 1 125 28" ] || { printf 'first float at [%s], want [1 129 1 125 28]\n' "$first" >&2; exit 1; }
    [ "$floats" = 2 ] || { printf 'second M-f left %s floats, want 2\n' "$floats" >&2; exit 1; }
    printf 'M-f opens a quarter float in the top-right snap cell, a second one cascades\n'
else
    tmux -L "float-bind-probe-$$" kill-server 2>/dev/null || true
    printf 'SKIP real-server M-f check: this tmux has no floating panes\n'
fi

# Border buttons [t][z][x] draw only on floats, and [x] kills without a menu.
rg --no-config -F '#{?#{&&:#{mouse},#{pane_floating_flag}},#[align=right]#[range=control|7]' "$CONF" >/dev/null
rg --no-config -F 'bind -T root MouseDown1Control9 kill-pane -t =' "$CONF" >/dev/null
printf 'border buttons are float-only and [x] kills without confirmation\n'
