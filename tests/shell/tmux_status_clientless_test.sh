#!/usr/bin/env bash
set -eo pipefail

# tmuxinator builds every session detached at login, so the status hooks fire on
# a server with no client attached. `tmux refresh-client -S` returns 1 there,
# and run-shell reports that as "'<command>' returned 1" into the first pane
# that later attaches. Run each hook body verbatim on a clientless server and
# assert it exits 0.

CONF="$HOME/dev/dotfiles/.tmux.conf"
REAL_TMUX=$(command -v tmux)
T=$(mktemp -d)
SOCK="status-clientless-$$"
trap '"$REAL_TMUX" -L "$SOCK" kill-server 2>/dev/null || true; rm -rf "$T"' EXIT

mkdir -p "$T/cache"
"$REAL_TMUX" -L "$SOCK" -f /dev/null new-session -d -s status-clientless
"$REAL_TMUX" -L "$SOCK" set-environment -g TMUX_TASK_CACHE_DIR "$T/cache"
"$REAL_TMUX" -L "$SOCK" set-environment -g TMUX_TASK_LOCK_FILE "$T/update.lock"

if [ -n "$("$REAL_TMUX" -L "$SOCK" list-clients 2>/dev/null)" ]; then
    printf 'FAIL: probe server has a client attached, test proves nothing\n'
    exit 1
fi

status=0
while IFS= read -r line; do
    hook=${line#set-hook -g }; hook=${hook%% *}
    # The conf line is: set-hook -g <hook> 'run-shell [-b] "<body>"'
    # Take the body between the first and last double quote and unescape it.
    body=${line#*\"}; body=${body%\"*}; body=${body//\\\"/\"}
    # #{hook_client} expands to the empty string when no client exists.
    body=${body//'#{hook_client}'/}
    printf '%s\n' "$body" > "$T/body.sh"
    rm -f "$T/rc"
    "$REAL_TMUX" -L "$SOCK" run-shell "sh '$T/body.sh' >'$T/out' 2>&1; echo \$? > '$T/rc'"
    for _ in $(seq 1 50); do
        [ -s "$T/rc" ] && break
        sleep 0.1
    done
    rc=$(cat "$T/rc" 2>/dev/null || echo "no-rc")
    if [ "$rc" != "0" ]; then
        printf 'FAIL: %s body exits %s with no client attached\n' "$hook" "$rc"
        printf '  body: %s\n' "$body"
        printf '  output: %s\n' "$(cat "$T/out" 2>/dev/null || true)"
        status=1
    fi
    if [ -s "$T/out" ]; then
        printf 'FAIL: %s body wrote output with no client attached\n' "$hook"
        printf '  output: %s\n' "$(cat "$T/out")"
        status=1
    fi
done < <(rg --no-config '^set-hook -g (client-session-changed|after-select-pane|after-select-window) ' "$CONF")

if [ "$status" -eq 0 ]; then
    printf 'PASS: status hooks stay silent and exit 0 on a clientless server\n'
fi
exit "$status"
