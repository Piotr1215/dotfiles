#!/usr/bin/env bash
# Send keys to registered Claude tmux sessions
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="${SCRIPT_DIR}/__send_keys_to_claude.py"

# Check if libtmux is installed
if ! python3 -c "import libtmux" 2>/dev/null; then
    echo "Installing libtmux..."
    pip3 install --user libtmux
fi

# Pass all arguments to Python script
exec python3 "$PYTHON_SCRIPT" "$@"