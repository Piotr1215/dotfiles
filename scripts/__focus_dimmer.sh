#!/usr/bin/env bash
set -eo pipefail

DIM_OPACITY="${DIM_OPACITY:-0xe6666666}"
declare -A managed_windows

window_exists() {
    xprop -id "$1" WM_CLASS &>/dev/null
}

safe_window_op() {
    local win_id="$1" operation="$2"
    window_exists "$win_id" && eval "$operation" 2>/dev/null
}

apply_focus_dimming() {
    local focused_window="$1"
    local visible_windows window_class

    visible_windows=$(xdotool search --onlyvisible --name ".*" 2>/dev/null) || return

    for win_id in $visible_windows; do
        window_class=$(xprop -id "$win_id" WM_CLASS 2>/dev/null) || continue

        if [[ "$window_class" =~ firefox|Navigator|Alacritty|Slack|Code|Chrome|chromium|Obsidian|Discord|Spotify|Thunderbird ]]; then
            managed_windows["$win_id"]=1
            if [[ "$win_id" == "$focused_window" ]]; then
                safe_window_op "$win_id" "xprop -id '$win_id' -remove _NET_WM_WINDOW_OPACITY"
            else
                safe_window_op "$win_id" "xprop -id '$win_id' -f _NET_WM_WINDOW_OPACITY 32c -set _NET_WM_WINDOW_OPACITY '$DIM_OPACITY'"
            fi
        fi
    done
}

cleanup() {
    for win_id in $(xdotool search --onlyvisible --name ".*" 2>/dev/null); do
        xprop -id "$win_id" -remove _NET_WM_WINDOW_OPACITY 2>/dev/null || true
    done
    exit 0
}

trap cleanup EXIT INT TERM

echo "Starting event-based focus dimmer..."

# Event-based: xprop -spy triggers only on _NET_ACTIVE_WINDOW changes
xprop -spy -root _NET_ACTIVE_WINDOW 2>/dev/null | while read -r _; do
    focused=$(xdotool getwindowfocus 2>/dev/null) || continue
    apply_focus_dimming "$focused"
done