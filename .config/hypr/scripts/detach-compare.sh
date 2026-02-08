#!/usr/bin/env bash
set -eo pipefail

# Detach active browser tab into new window, then side-by-side (layout 3)
CLIENTS=$(hyprctl clients -j)
browser=$(echo "$CLIENTS" | jq -r '[.[] | select((.class == "librewolf" or .class == "LibreWolf" or .class == "firefox" or .class == "Firefox") and .mapped == true and .hidden == false)] | .[0].address // empty')
[[ -z "$browser" ]] && exit 0

hyprctl dispatch focuswindow "address:$browser"
sleep 0.2
YDOTOOL_SOCKET=/tmp/.ydotool_socket ydotool key 42:1 56:1 32:1 32:0 56:0 42:0
sleep 0.5
~/.config/hypr/scripts/layouts.sh 3
