#!/usr/bin/env bash
set -eo pipefail

# Hyprland equivalent of __layouts.sh (X11)
# Uses hyprctl + jq instead of xdotool/wmctrl/xprop

if [[ -z "$1" ]]; then
	echo "Usage: $0 {1|2|3|4|5|6|7|8|9|10}"
	exit 1
fi

# Cache client list (single hyprctl call per invocation)
CLIENTS=$(hyprctl clients -j)
# Use focused monitor (handles clamshell/multi-monitor)
# Account for reserved area (waybar) via monitor's reserved field [left, top, right, bottom]
read -r MON_W MON_H BAR_TOP < <(hyprctl monitors -j | jq -r '[.[] | select(.focused == true)] | .[0] | "\(.width) \(.height) \(.reserved[1])"')
HALF_W=$((MON_W / 2))
USABLE_H=$((MON_H - BAR_TOP))

#{{{ Utility Functions

find_window() {
	echo "$CLIENTS" | jq -r \
		"[.[] | select(.class == \"$1\" and .mapped == true and .hidden == false)] | .[0].address // empty"
}

find_browser() {
	local addr
	for class in librewolf LibreWolf firefox Firefox Navigator; do
		addr=$(find_window "$class")
		[[ -n "$addr" ]] && { echo "$addr"; return; }
	done
}

find_all_browsers() {
	echo "$CLIENTS" | jq -r \
		'[.[] | select((.class == "librewolf" or .class == "LibreWolf" or .class == "firefox" or .class == "Firefox" or .class == "Navigator") and .mapped == true)] | .[].address'
}

find_two_browsers() {
	echo "$CLIENTS" | jq -r \
		'[.[] | select((.class == "librewolf" or .class == "LibreWolf" or .class == "firefox" or .class == "Firefox" or .class == "Navigator") and .mapped == true and .hidden == false)] | .[0:2] | .[].address'
}

cycle_browser() {
	local key="$1" state="/tmp/hypr-browser-cycle-${key}"
	local last=""
	[[ -f "$state" ]] && last=$(cat "$state")
	mapfile -t all < <(find_all_browsers)
	[[ ${#all[@]} -eq 0 ]] && return 1
	local next="${all[0]}"
	for i in "${!all[@]}"; do
		if [[ "${all[$i]}" == "$last" ]]; then
			next="${all[$(( (i + 1) % ${#all[@]} ))]}"
			break
		fi
	done
	echo "$next" > "$state"
	echo "$next"
}

# Position a floating window at exact coordinates
# Handles: unfullscreen → ensure floating → move/resize
place() {
	local addr="$1" x="$2" y="$3" w="$4" h="$5"
	# Must focus first - fullscreen/float toggles act on focused window context
	hyprctl dispatch focuswindow "address:$addr"
	# Unfullscreen if needed (live query - cache may be stale after maximize)
	local fs
	fs=$(hyprctl clients -j | jq -r ".[] | select(.address == \"$addr\") | .fullscreen")
	[[ "$fs" != "0" && "$fs" != "null" ]] && hyprctl dispatch fullscreen 0
	# Ensure floating (live query)
	local fl
	fl=$(hyprctl clients -j | jq -r ".[] | select(.address == \"$addr\") | .floating")
	[[ "$fl" != "true" ]] && hyprctl dispatch togglefloating "address:$addr"
	hyprctl --batch \
		"dispatch movewindowpixel exact $x $y,address:$addr ; dispatch resizewindowpixel exact $w $h,address:$addr"
}

focus() {
	hyprctl dispatch focuswindow "address:$1"
}

minimize_others() {
	local filter=""
	for addr in "$@"; do
		filter+=" and .address != \"$addr\""
	done
	hyprctl clients -j | jq -r ".[] | select(.floating == true and .mapped == true and .hidden == false${filter}) | .address" | while read -r addr; do
		hyprctl dispatch movetoworkspacesilent "special:hidden,address:$addr"
	done
}

restore_from_hidden() {
	hyprctl clients -j | jq -r '.[] | select(.workspace.name == "special:hidden") | .address' | while read -r addr; do
		hyprctl dispatch movetoworkspacesilent "1,address:$addr"
	done
	CLIENTS=$(hyprctl clients -j)
}

maximize() {
	restore_from_hidden
	place "$1" 0 "$BAR_TOP" "$MON_W" "$USABLE_H"
	minimize_others "$1"
}

#}}}

#{{{ Layout Functions

# 1: Maximize Alacritty
max_alacritty() {
	local win
	win=$(find_window "Alacritty")
	[[ -z "$win" ]] && { echo "No Alacritty window found."; return 1; }
	maximize "$win"
}

# 2: Browser left, Alacritty right (50/50) - cycles browser on repeat
alacritty_firefox_vertical() {
	restore_from_hidden
	local alacritty
	alacritty=$(find_window "Alacritty")
	[[ -z "$alacritty" ]] && { echo "No Alacritty window found."; return 1; }
	local browser
	browser=$(cycle_browser "layout2")
	[[ -z "$browser" ]] && { echo "No browser window found."; return 1; }
	place "$browser" 0 "$BAR_TOP" "$HALF_W" "$USABLE_H"
	place "$alacritty" "$HALF_W" "$BAR_TOP" "$HALF_W" "$USABLE_H"
	minimize_others "$browser" "$alacritty"
	focus "$alacritty"
}

# 3: Two browser windows side by side
firefox_firefox_vertical() {
	restore_from_hidden
	local wins
	mapfile -t wins < <(find_two_browsers)
	if [[ ${#wins[@]} -lt 2 ]]; then
		echo "Need 2 browser windows, found ${#wins[@]}."
		[[ ${#wins[@]} -eq 1 ]] && maximize "${wins[0]}"
		return 1
	fi
	place "${wins[0]}" 0 "$BAR_TOP" "$HALF_W" "$USABLE_H"
	place "${wins[1]}" "$HALF_W" "$BAR_TOP" "$HALF_W" "$USABLE_H"
	minimize_others "${wins[0]}" "${wins[1]}"
	focus "${wins[1]}"
}

# 4: Slack left, browser right
slack_firefox_vertical() {
	restore_from_hidden
	local slack browser
	slack=$(find_window "Slack")
	browser=$(find_browser)
	if [[ -z "$slack" ]]; then
		echo "No Slack, falling back to alacritty+firefox."
		alacritty_firefox_vertical
		return
	fi
	[[ -z "$browser" ]] && { echo "No browser window found."; return 1; }
	place "$slack" 0 "$BAR_TOP" "$HALF_W" "$USABLE_H"
	place "$browser" "$HALF_W" "$BAR_TOP" "$HALF_W" "$USABLE_H"
	minimize_others "$slack" "$browser"
	focus "$browser"
}

# 5: Maximize browser (cycles through all browser windows)
max_firefox() {
	restore_from_hidden
	local win
	win=$(cycle_browser "layout5")
	[[ -z "$win" ]] && { echo "No browser window found."; return 1; }
	place "$win" 0 "$BAR_TOP" "$MON_W" "$USABLE_H"
	minimize_others "$win"
}

# 6: Maximize Slack
max_slack() {
	local win
	win=$(find_window "Slack")
	[[ -z "$win" ]] && { echo "No Slack window found."; return 1; }
	maximize "$win"
}

# 7: Two browsers top, Alacritty bottom
firefox_firefox_alacritty() {
	restore_from_hidden
	local alacritty
	mapfile -t browsers < <(find_two_browsers)
	alacritty=$(find_window "Alacritty")
	if [[ ${#browsers[@]} -lt 2 ]] || [[ -z "$alacritty" ]]; then
		echo "Need 2 browsers + 1 Alacritty."
		alacritty_firefox_vertical
		return 1
	fi
	local top_h=$((USABLE_H / 2))
	local bot_h=$((USABLE_H - top_h))
	local bot_y=$((BAR_TOP + top_h))
	place "${browsers[0]}" 0 "$BAR_TOP" "$HALF_W" "$top_h"
	place "${browsers[1]}" "$HALF_W" "$BAR_TOP" "$HALF_W" "$top_h"
	place "$alacritty" 0 "$bot_y" "$MON_W" "$bot_h"
	minimize_others "${browsers[0]}" "${browsers[1]}" "$alacritty"
	focus "$alacritty"
}

# 8: Slack left, Alacritty right
slack_alacritty_vertical() {
	restore_from_hidden
	local slack alacritty
	slack=$(find_window "Slack")
	alacritty=$(find_window "Alacritty")
	if [[ -z "$slack" ]]; then
		echo "No Slack, falling back to alacritty+firefox."
		alacritty_firefox_vertical
		return
	fi
	[[ -z "$alacritty" ]] && { echo "No Alacritty window found."; return 1; }
	place "$slack" 0 "$BAR_TOP" "$HALF_W" "$USABLE_H"
	place "$alacritty" "$HALF_W" "$BAR_TOP" "$HALF_W" "$USABLE_H"
	minimize_others "$slack" "$alacritty"
	focus "$alacritty"
}

# 9: Alacritty at 9:16 aspect ratio
alacritty_resize_9_16() {
	local alacritty height width
	alacritty=$(find_window "Alacritty")
	[[ -z "$alacritty" ]] && { echo "No Alacritty window found."; return 1; }
	height=$((USABLE_H - 60))
	width=$((height * 9 / 16))
	place "$alacritty" 50 "$((BAR_TOP + 30))" "$width" "$height"
	focus "$alacritty"
}

# 10: Browser (ChatGPT) left, Alacritty right
chatgpt_alacritty_vertical() {
	alacritty_firefox_vertical
}

#}}}

case $1 in
1) max_alacritty ;;
2) alacritty_firefox_vertical ;;
3) firefox_firefox_vertical ;;
4) slack_firefox_vertical ;;
5) max_firefox ;;
6) max_slack ;;
7) firefox_firefox_alacritty ;;
8) slack_alacritty_vertical ;;
9) alacritty_resize_9_16 ;;
10) chatgpt_alacritty_vertical ;;
*) echo "Usage: $0 {1|2|3|4|5|6|7|8|9|10}"; exit 1 ;;
esac
