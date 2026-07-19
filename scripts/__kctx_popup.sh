#!/usr/bin/env bash
set -eo pipefail

KCTX_BIN="${KCTX_BIN:-$HOME/.local/bin/kctx}"
target_pane="$(tmux display-message -p '#{pane_id}')"

if "$KCTX_BIN" use --pane "$target_pane"; then
    picker_status=0
else
    picker_status=$?
fi
tmux refresh-client -S 2>/dev/null || true
if [[ $picker_status -ne 0 ]]; then
    printf '\nContext switch failed (exit %s).\n' "$picker_status" >&2
    if [[ -t 0 ]]; then
        read -r -n 1 -s -p 'Press any key to close this popup.' || true
        printf '\n' >&2
    fi
fi
exit "$picker_status"
