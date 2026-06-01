#!/usr/bin/env bash

# __open_repo.sh
# Open the current repo in the browser and swap to the alacritty/browser split.
# If the current branch has an open PR, open the PR view instead of the repo home.

set -eo pipefail

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	echo "Not inside a git repository" >&2
	exit 1
fi

# Prefer the PR for the current branch; fall back to the branch view
# (mirrors the lazygit "open current branch in browser" binding).
url=$(gh pr view --json url --jq .url 2>/dev/null) || url=""
if [[ -z "$url" ]]; then
	branch=$(git branch --show-current)
	url=$(gh browse --no-browser --branch "$branch" 2>/dev/null) || {
		echo "No GitHub remote found (or gh not authenticated)" >&2
		exit 1
	}
fi

# Open quietly, focus the browser, then tile into the alacritty/browser split.
xdg-open "$url" >/dev/null 2>&1
__focus_browser.sh
~/dev/dotfiles/scripts/__layouts.sh 2
