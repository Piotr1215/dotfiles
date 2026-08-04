#!/usr/bin/env bash
set -euo pipefail

exec "$(dirname "$0")/__toggle_agent_label.sh" claude "${1:-}"
