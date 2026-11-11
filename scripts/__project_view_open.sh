#!/usr/bin/env bash
set -eo pipefail

view_dir="${HOME}/.local/state/project-views"
shopt -s nullglob
files=("${view_dir}"/*.md)
if ((${#files[@]} == 0)); then
    printf 'No project views found in %s\n' "$view_dir" >&2
    exit 1
fi

choice=$(printf '%s\n' "${files[@]}" | fzf --prompt='Project view: ' --with-nth=-1 --delimiter=/) || exit 0
if command -v glow >/dev/null 2>&1; then
    exec glow -p "$choice"
fi
exec less -R "$choice"
