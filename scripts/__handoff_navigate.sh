#!/usr/bin/env bash
set -eo pipefail
# S opens the selected handoff; all URLs remain individual argv values.
root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
exec python3 "$root/__handoff_navigate.py" "$@"
