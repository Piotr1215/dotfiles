#!/usr/bin/env bash
# Cycle the selected task's effort: M -> H -> X -> M.
set -euo pipefail

raw="${1:?task uuid or id required}"
uuid=$(task _get "${raw}.uuid")
[[ -n "$uuid" ]] || { echo "Task not found: $raw" >&2; exit 1; }

effort=$(task _get "${uuid}.effort")
if [[ -z "$effort" ]]; then
    effort=$(task _get rc.uda.effort.default)
fi

case "${effort:-H}" in
    M|medium) next=H ;;
    H|high) next=X ;;
    X|xhigh) next=M ;;
    *) echo "Invalid effort: $effort. Set it to M, H, or X." >&2; exit 1 ;;
esac

# A bare UUID filter loads every task in the database; `<id> uuid:<uuid>`
# reads pending tasks only. A completed task has id 0 and keeps the bare UUID.
id=$(task _get "${uuid}.id")
filter=("$uuid")
if [[ -n "$id" && "$id" != 0 ]]; then
    filter=("$id" "uuid:$uuid")
fi
task rc.bulk=0 rc.confirmation=off rc.verbose=nothing "${filter[@]}" modify "effort:$next"
