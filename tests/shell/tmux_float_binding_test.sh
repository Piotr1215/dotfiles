#!/usr/bin/env bash
set -euo pipefail

CONF="${0%/*}/../../.tmux.conf"

rg --no-config -F \
    "bind-key '*' if-shell \"tmux list-panes -t '#{window_id}' -F '#{pane_floating_flag}' | grep -q '^1$'\"" \
    "$CONF" >/dev/null
rg --no-config -F \
    "bind-key -n M-f if-shell \"tmux list-panes -t '#{window_id}' -F '#{pane_floating_flag}' | grep -q '^1$'\"" \
    "$CONF" >/dev/null
rg --no-config -F "new-pane -c '#{pane_current_path}' -x 50% -y 50% -X '#{e|-:50,#{e|*:2,#{n:#{P:#{?pane_floating_flag,x,}}}}}%' -Y '#{e|*:2,#{n:#{P:#{?pane_floating_flag,x,}}}}' zsh" "$CONF" >/dev/null
rg --no-config -F "new-pane -c '#{pane_current_path}' -x 50% -y 50% zsh ; move-pane -P top-right" "$CONF" >/dev/null

rg --no-config -F "break-pane -W -X '#{e|-:#{@float_x},1}' -Y '#{e|-:#{@float_y},1}'" "$CONF" >/dev/null

printf 'prefix * and M-f open a quarter float top-right with a card fan, prefix @ restores a float\n'

# On a real tmux 3.8 server, in a 255x61 window (odd width, where -X 50% alone
# lands a column short): M-f four times gives a quarter float in exactly the
# top-right snap cell, then each next one a card further down-left. prefix t
# floats a tile into the same spots and tiles a float back.
if tmux -L "float-bind-probe-$$" -f /dev/null new-session -d -s p -x 80 -y 24 \; new-pane -x 20 -y 8 2>/dev/null; then
    tmux -L "float-bind-probe-$$" kill-server
    sock="float-bind-$$"
    tmp=$(mktemp)
    awk '/^bind-key -n M-f /{n=3} n&&n--' "$CONF" > "$tmp"
    awk '/^bind t /{p=1} p{print} p&&/^}/{exit}' "$CONF" >> "$tmp"
    geo='#{pane_floating_flag} #{pane_left},#{pane_top} #{pane_width}x#{pane_height}'
    tmux -L "$sock" -f /dev/null new-session -d -s t -x 255 -y 61
    tmux -L "$sock" source-file "$tmp"
    body=$(tmux -L "$sock" list-keys -T root M-f | sed -E 's/^bind-key +-T root +M-f +//')
    for _ in 1 2 3 4; do tmux -L "$sock" source-file - <<<"$body"; done
    fan=$(tmux -L "$sock" list-panes -t t -F "$geo" | awk '$1==1{print $2, $3}' | sort -t, -k2,2n | paste -sd'|')
    # prefix t: three tiles, float one, float another, then tile the second back.
    tmux -L "$sock" new-window -t t:
    tmux -L "$sock" split-window -h -t t:
    tmux -L "$sock" split-window -h -t t:
    tbody=$(tmux -L "$sock" list-keys -T prefix t | sed -E 's/^bind-key +-T prefix +t +//')
    tmux -L "$sock" source-file - <<<"$tbody"
    tmux -L "$sock" select-pane -t "$(tmux -L "$sock" list-panes -t t: -F '#{pane_floating_flag} #{pane_id}' | awk '$1==0{print $2; exit}')"
    tmux -L "$sock" source-file - <<<"$tbody"
    tfan=$(tmux -L "$sock" list-panes -t t: -F "$geo" | awk '$1==1{print $2, $3}' | sort -t, -k2,2n | paste -sd'|')
    tmux -L "$sock" source-file - <<<"$tbody"
    tiles=$(tmux -L "$sock" list-panes -t t: -F '#{pane_floating_flag}' | grep -c '^0$')
    tmux -L "$sock" kill-server
    rm -f "$tmp"
    want='129,1 125x28|123,3 125x28|118,5 125x28|113,7 125x28'
    [ "$fan" = "$want" ] || { printf 'M-f x4 floats at [%s], want [%s]\n' "$fan" "$want" >&2; exit 1; }
    printf 'M-f opens a quarter float in the top-right snap cell, later ones fan out like cards\n'
    want='129,1 125x28|123,3 125x28'
    [ "$tfan" = "$want" ] || { printf 'prefix t x2 floats at [%s], want [%s]\n' "$tfan" "$want" >&2; exit 1; }
    [ "$tiles" = 2 ] || { printf 'prefix t on a float left %s tiled panes, want 2\n' "$tiles" >&2; exit 1; }
    printf 'prefix t floats tiles into the same cells and tiles a float back\n'
else
    tmux -L "float-bind-probe-$$" kill-server 2>/dev/null || true
    printf 'SKIP real-server M-f check: this tmux has no floating panes\n'
fi

# Border buttons [t][z][x] draw only on floats, and [x] kills without a menu.
rg --no-config -F '#{?#{&&:#{mouse},#{pane_floating_flag}},#[align=right]#[range=control|7]' "$CONF" >/dev/null
rg --no-config -F 'bind -T root MouseDown1Control9 kill-pane -t =' "$CONF" >/dev/null
printf 'border buttons are float-only and [x] kills without confirmation\n'
