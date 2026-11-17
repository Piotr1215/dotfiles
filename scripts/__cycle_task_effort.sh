#!/usr/bin/env bash
# Cycle the selected task's effort: L -> M -> H -> X -> Z -> L
# (low, medium, high, xhigh, max; Piotr, 17 Nov).
set -euo pipefail

raw="${1:?task uuid or id required}"
uuid=$(task _get "${raw}.uuid")
[[ -n "$uuid" ]] || { echo "Task not found: $raw" >&2; exit 1; }

effort=$(task _get "${uuid}.effort")
if [[ -z "$effort" ]]; then
    effort=$(task _get rc.uda.effort.default)
fi

case "${effort:-H}" in
    L|low) next=M ;;
    M|medium) next=H ;;
    H|high) next=X ;;
    X|xhigh) next=Z ;;
    Z|max) next=L ;;
    *) echo "Invalid effort: $effort. Set it to L, M, H, X, or Z." >&2; exit 1 ;;
esac

# A bare UUID filter loads every task in the database; `<id> uuid:<uuid>`
# reads pending tasks only. A completed task has id 0 and keeps the bare UUID.
id=$(task _get "${uuid}.id")
filter=("$uuid")
if [[ -n "$id" && "$id" != 0 ]]; then
    filter=("$id" "uuid:$uuid")
fi
task rc.bulk=0 rc.confirmation=off rc.verbose=nothing "${filter[@]}" modify "effort:$next"
