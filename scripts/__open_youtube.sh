#!/usr/bin/env bash
set -eo pipefail

# Always open YouTube in LibreWolf "Home" profile.
# Passing -P to an already-running profile causes the URL to be dropped (profile lock),
# so only pass -P on cold start.
if pgrep -f 'librewolf.*-P Home' >/dev/null 2>&1; then
    flatpak run io.gitlab.librewolf-community "https://youtube.com" &
else
    flatpak run io.gitlab.librewolf-community -P "Home" "https://youtube.com" &
fi
sleep 2
wmctrl -a librewolf
