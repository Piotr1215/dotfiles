#!/usr/bin/env bash
set -eo pipefail

# Focus the active browser window (Chrome for work, LibreWolf for home)
if [[ -f /tmp/timeoff_mode ]]; then
	wmctrl -a LibreWolf
else
	wmctrl -a "Google Chrome"
fi
