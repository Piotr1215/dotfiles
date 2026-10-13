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

# _get reads one task. `_tags <uuid>` and a bare UUID filter load every task
# in the database; `<id> uuid:<uuid>` reads pending tasks only. A completed
# task has id 0 and keeps the bare UUID.
current_tags=$(task _get "$uuid.tags")
id=$(task _get "$uuid.id")
filter=("$uuid")
if [[ -n "$id" && "$id" != 0 ]]; then
  filter=("$id" "uuid:$uuid")
fi
if grep -qw "$runner" <<<"$current_tags"; then
  task rc.bulk=0 rc.confirmation=off rc.verbose=nothing "${filter[@]}" modify "-$runner"
else
  task rc.bulk=0 rc.confirmation=off rc.verbose=nothing "${filter[@]}" modify "+$runner" "-$other"
fi
