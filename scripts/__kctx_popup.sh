#!/usr/bin/env bash
set -eo pipefail

KCTX_BIN="${KCTX_BIN:-$HOME/.local/bin/kctx}"
target_pane="$(tmux display-message -p '#{pane_id}')"

if "$KCTX_BIN" pick "$target_pane"; then
    picker_status=0
else
    picker_status=$?
fi
tmux refresh-client -S 2>/dev/null || true
exit "$picker_status"
