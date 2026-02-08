#!/usr/bin/env bash
set -eo pipefail

# Toggle show desktop - send all windows to special workspace or bring them back
hidden=$(hyprctl clients -j | jq '[.[] | select(.workspace.name == "special:desktop")] | length')

if ((hidden > 0)); then
	hyprctl clients -j | jq -r '.[] | select(.workspace.name == "special:desktop") | .address' | while read -r addr; do
		hyprctl dispatch movetoworkspacesilent 1,address:"$addr"
	done
else
	hyprctl clients -j | jq -r '.[] | select(.mapped == true and .hidden == false) | .address' | while read -r addr; do
		hyprctl dispatch movetoworkspacesilent special:desktop,address:"$addr"
	done
fi
