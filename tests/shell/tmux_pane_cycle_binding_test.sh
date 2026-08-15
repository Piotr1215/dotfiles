#!/usr/bin/env bash
set -euo pipefail

CONF="${0%/*}/../../.tmux.conf"

rg --no-config -Fx 'bind-key -n C-M-PageUp select-pane -t :.-' "$CONF" >/dev/null
rg --no-config -Fx 'bind-key -n C-M-PageDown select-pane -t :.+' "$CONF" >/dev/null

printf 'pane cycle bindings: Ctrl+Alt+PageUp previous, Ctrl+Alt+PageDown next\n'
