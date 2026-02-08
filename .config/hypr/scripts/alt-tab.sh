#!/usr/bin/env bash
set -eo pipefail

direction="next"
[[ "$1" == "--reverse" ]] && direction="prev"

active=$(hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty')

# Stable order by address (doesn't change on focus like focusHistoryID does)
mapfile -t addrs < <(hyprctl clients -j | jq -r '[.[] | select(.mapped == true)] | sort_by(.address) | .[].address')
count=${#addrs[@]}
[[ $count -lt 2 ]] && exit 0

current_idx=0
for i in "${!addrs[@]}"; do
    [[ "${addrs[$i]}" == "$active" ]] && { current_idx=$i; break; }
done

if [[ "$direction" == "next" ]]; then
    target_idx=$(( (current_idx + 1) % count ))
else
    target_idx=$(( (current_idx - 1 + count) % count ))
fi

target="${addrs[$target_idx]}"

# Bring back from special:hidden if needed
ws=$(hyprctl clients -j | jq -r ".[] | select(.address == \"$target\") | .workspace.name")
if [[ "$ws" == special:* ]]; then
    current_ws=$(hyprctl activeworkspace -j | jq -r '.id')
    hyprctl dispatch movetoworkspacesilent "${current_ws},address:${target}"
fi

hyprctl dispatch focuswindow "address:${target}"
hyprctl dispatch alterzorder top
