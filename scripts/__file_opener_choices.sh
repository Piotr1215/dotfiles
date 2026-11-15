#!/usr/bin/env bash
# Stream sessions first so M-x can switch before the file scan finishes.
set -euo pipefail

"$(dirname "${BASH_SOURCE[0]}")/__tmux_session_choices.sh" list
zoxide query -l || true

cache_file="${FILE_OPENER_CACHE_FILE:-/tmp/file_opener_cache_$USER}"
if [[ -f "$cache_file" ]] && (( $(date +%s) - $(stat -c %Y "$cache_file") < 60 )); then
    cat "$cache_file"
    exit 0
fi

# Publish only complete scans. Closing the picker or a failed scan must not
# leave a truncated cache that hides files on the next invocation.
cache_tmp=$(mktemp "${cache_file}.XXXXXX")
trap 'rm -f "$cache_tmp"' EXIT
if fd --type f --hidden --absolute-path --color never \
    --exclude .git --exclude node_modules --exclude .cache --exclude image-cache \
    --exclude plugins --exclude stats-cache.json --exclude claude-wt-worktrees \
    --exclude vendor --changed-within 7d --print0 \
    . "$HOME/dev" "$HOME/loft" "$HOME/.config/nvim" "$HOME/.claude" 2>/dev/null \
    | xargs -0 -r stat --format '%Y %n' 2>/dev/null \
    | sort -rn | cut -d' ' -f2- > "$cache_tmp"; then
    mv -f "$cache_tmp" "$cache_file"
fi
[[ ! -f "$cache_file" ]] || cat "$cache_file"
