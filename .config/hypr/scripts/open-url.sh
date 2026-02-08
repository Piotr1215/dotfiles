#!/usr/bin/env bash
set -eo pipefail

# Open URL and focus browser window
xdg-open "$1" &
sleep 0.3
hyprctl clients -j | jq -r '[.[] | select((.class == "librewolf" or .class == "LibreWolf" or .class == "firefox" or .class == "Firefox") and .mapped == true)] | .[0].address // empty' | head -1 | while read -r addr; do
	[[ -n "$addr" ]] && hyprctl dispatch focuswindow "address:$addr"
done
