#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Open the Linear issue for the current tmux session/agent in the browser.
# The issue id is embedded in the session name (e.g. ai-agents-ENGAI-110).
# Intended to be bound to a tmux key with the session name:
#   bind-key -n M-a run-shell "~/dev/dotfiles/scripts/__open_pane_linear.sh '#{session_name}'"
# Sibling of __open_pane_pr.sh (M-p), which opens the pane's GitHub PR.

main() {
    local name="${1:-}"

    # Linear ids look like ENGAI-110, DEVOPS-123, DOC-7. Take the first match.
    if [[ ! "$name" =~ [A-Za-z]+-[0-9]+ ]]; then
        notify "no linear id in: ${name:-<empty>}"
        exit 0
    fi
    local id
    id=$(printf '%s' "${BASH_REMATCH[0]}" | tr '[:lower:]' '[:upper:]')

    DISPLAY="${DISPLAY:-:0}" xdg-open "https://linear.app/loft/issue/$id" >/dev/null 2>&1 &
    notify "opening Linear: $id"

    # Focus the browser, then arrange alacritty | browser side by side (layout #2).
    DISPLAY="${DISPLAY:-:0}" "$SCRIPT_DIR/__focus_browser.sh" >/dev/null 2>&1 || true
    sleep 0.8
    DISPLAY="${DISPLAY:-:0}" "$SCRIPT_DIR/__layouts.sh" 2 >/dev/null 2>&1 || true
}

# Surface a message in tmux if we're inside it, else stderr.
notify() {
    if [[ -n "$TMUX" ]]; then
        tmux display-message "$1"
    else
        echo "$1" >&2
    fi
}

main "$@"
