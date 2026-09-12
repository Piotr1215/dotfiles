#!/usr/bin/env bash
set -eo pipefail

export PATH="$HOME/dev/google-cloud-sdk/bin:$PATH"

KCTX_BIN="${KCTX_BIN:-$HOME/.local/bin/kctx}"
CLAUDE_NOTIFY="${KCTX_CLAUDE_NOTIFY:-$HOME/dev/dotfiles/scripts/__kctx_claude_notify.sh}"
target_pane="$(tmux display-message -p '#{pane_id}')"
connection_before="$(tmux show-options -pqv -t "$target_pane" @kctx_display 2>/dev/null || true)"

if "$KCTX_BIN" use --pane "$target_pane"; then
    picker_status=0
else
    picker_status=$?
fi
tmux refresh-client -S 2>/dev/null || true

# A Claude or Codex session in the target pane cannot see the swap: its
# environment is fixed at launch and the pane border is not in its context.
# Nudge it, but only on a real change, so re-picking the same connection stays
# silent. Detached so the popup closes first and a slow send never holds it open.
if [[ $picker_status -eq 0 ]]; then
    connection_after="$(tmux show-options -pqv -t "$target_pane" @kctx_display 2>/dev/null || true)"
    if [[ "$connection_after" != "$connection_before" && -x "$CLAUDE_NOTIFY" ]]; then
        tmux run-shell -b "$CLAUDE_NOTIFY $target_pane" 2>/dev/null || true
    fi
fi

if [[ $picker_status -ne 0 ]]; then
    printf '\nContext switch failed (exit %s).\n' "$picker_status" >&2
    if [[ -t 0 ]]; then
        read -r -n 1 -s -p 'Press any key to close this popup.' || true
        printf '\n' >&2
    fi
fi
exit "$picker_status"
