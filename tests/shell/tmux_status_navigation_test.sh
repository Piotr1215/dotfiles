#!/usr/bin/env bash
set -eo pipefail

# The status cache is session-scoped, but @claude_goal is pane-scoped. Moving
# to another window must therefore rebuild the cache from its active pane. Load
# only the navigation hooks into a private tmux server and assert on the cache
# they produce, so the test does not touch the live server.

CONF="$HOME/dev/dotfiles/.tmux.conf"
REAL_TMUX=$(command -v tmux)
T=$(mktemp -d)
SOCK="status-navigation-$$"
CACHE="$T/cache"
trap '"$REAL_TMUX" -L "$SOCK" kill-server 2>/dev/null || true; rm -rf "$T"' EXIT

mkdir -p "$CACHE"
rg --no-config '^set-hook -g (after-select-pane|after-select-window) ' "$CONF" > "$T/hooks.conf"
"$REAL_TMUX" -L "$SOCK" -f /dev/null new-session -d -s status-navigation -n first
"$REAL_TMUX" -L "$SOCK" new-window -d -t status-navigation -n second
"$REAL_TMUX" -L "$SOCK" set-option -p -t status-navigation:first @claude_goal 'first window goal'
"$REAL_TMUX" -L "$SOCK" set-option -p -t status-navigation:second @claude_goal 'second window goal'
"$REAL_TMUX" -L "$SOCK" set-environment -g TMUX_TASK_CACHE_DIR "$CACHE"
"$REAL_TMUX" -L "$SOCK" set-environment -g TMUX_TASK_LOCK_FILE "$T/update.lock"
"$REAL_TMUX" -L "$SOCK" source-file "$T/hooks.conf"

"$REAL_TMUX" -L "$SOCK" select-window -t status-navigation:second
for _ in $(seq 1 30); do
    [[ -r "$CACHE/status-navigation" ]] && break
    sleep 0.1
done
line=$(cat "$CACHE/status-navigation" 2>/dev/null || true)

if [[ "$line" != '🤖 second window goal | '* ]]; then
    printf 'FAIL: window selection did not rebuild the status cache\n'
    printf '  cache: %s\n' "${line:-<empty>}"
    exit 1
fi

printf 'PASS: window selection rebuilds the status cache from its active pane\n'
