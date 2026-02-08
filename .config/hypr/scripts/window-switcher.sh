#!/usr/bin/env bash
set -eo pipefail

# Show all open windows in wofi, focus selected one
selected=$(hyprctl clients -j | jq -r '.[] | select(.mapped == true) | "\(.address) | \(.class) : \(.title)"' | wofi --dmenu --prompt "Windows" --insensitive)

[[ -z "$selected" ]] && exit 0

addr=$(echo "$selected" | cut -d'|' -f1 | tr -d ' ')
ws=$(hyprctl clients -j | jq -r ".[] | select(.address == \"$addr\") | .workspace.name")

# Bring back from special workspace if hidden
[[ "$ws" == special:* ]] && hyprctl dispatch movetoworkspacesilent "1,address:$addr"

hyprctl dispatch focuswindow "address:$addr"
