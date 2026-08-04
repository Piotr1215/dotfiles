#!/usr/bin/env bash
set -euo pipefail

runner="${1:-}"
uuid="${2:-}"

case "$runner" in
  claude) other="codex" ;;
  codex) other="claude" ;;
  *)
    printf 'usage: %s {claude|codex} TASK_UUID\n' "$0" >&2
    exit 2
    ;;
esac

[[ -n "$uuid" ]] || {
  printf 'task uuid is required\n' >&2
  exit 2
}

current_tags=$(task _tags "$uuid")
if grep -qw "$runner" <<<"$current_tags"; then
  task rc.bulk=0 rc.confirmation=off "$uuid" modify "-$runner"
else
  task rc.bulk=0 rc.confirmation=off "$uuid" modify "+$runner" "-$other"
fi
