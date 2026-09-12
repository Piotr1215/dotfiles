#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Open the GitHub PR for the git branch in a given directory, in the browser.
# Intended to be bound to a tmux key with the pane's current path:
#   bind-key -n M-P run-shell "~/dev/dotfiles/scripts/__open_pane_pr.sh '#{pane_current_path}'"
# Mirrors the "PR #N" badge Claude Code shows for the current branch.

main() {
    local target_dir="${1:-$PWD}"

    if [[ ! -d "$target_dir" ]]; then
        notify "no such dir: $target_dir"
        exit 1
    fi
    cd "$target_dir"

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        notify "not a git repo: $target_dir"
        exit 0
    fi

    # gh resolves the PR from the current branch's upstream automatically.
    local url
    url=$(DISPLAY="${DISPLAY:-:0}" gh pr view --json url --jq .url 2>/dev/null || true)

    if [[ -z "$url" ]]; then
        notify "no PR for $(git branch --show-current 2>/dev/null || echo branch)"
        exit 0
    fi

    DISPLAY="${DISPLAY:-:0}" xdg-open "$url" >/dev/null 2>&1 &
    notify "opening PR: $url"

    # arrange alacritty | browser side by side (layout #2 = alacritty_firefox_vertical)
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
