#!/usr/bin/env bash
set -euo pipefail

exec "$(dirname "$0")/__toggle_agent_label.sh" codex "${1:-}"
