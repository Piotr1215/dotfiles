#!/usr/bin/env bash
# Match the handoffs report without inheriting the work context.
set -eo pipefail
count=$(${TUI_HANDOFF_TASK_COMMAND:-task} rc.context=none rc.hooks=off rc.verbose=nothing status:pending +piotr count 2>/dev/null) || exit 0
[[ "$count" =~ ^[0-9]+$ ]] || exit 0
printf ' H:%s' "$count"
