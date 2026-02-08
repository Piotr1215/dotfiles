#!/usr/bin/env bash

# Show all open windows in wofi, focus selected one

selected=$(hyprctl clients -j | jq -r '
    [.[] | select(.mapped == true)] |
    sort_by(.focusHistoryID) |
    .[] | "\(.address) :: \(.class): \(.title)"
' | wofi --dmenu --prompt "Windows" --insensitive) || exit 0

[[ -z "$selected" ]] && exit 0

addr="${selected%% ::*}"
[[ -z "$addr" ]] && exit 0

# Bring back from special workspace if hidden
ws=$(hyprctl clients -j | jq -r ".[] | select(.address == \"$addr\") | .workspace.name")
if [[ "$ws" == special:* ]]; then
    current_ws=$(hyprctl activeworkspace -j | jq -r '.id')
    hyprctl dispatch movetoworkspacesilent "${current_ws},address:${addr}"
fi

hyprctl dispatch focuswindow "address:${addr}"
