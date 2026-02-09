#!/usr/bin/env bash

# PROJECT: window_manager
# Add source and line number wher running in debug mode: __run_with_xtrace.sh __layouts.sh
# Set new line and tab for word splitting
IFS=$'\n\t'

if [[ -z "$1" ]]; then
	echo "Usage: $0 {1|2|3|4|5|6|7|8|9|10}"
	exit 1
fi

#{{{ Utility Functions

# DBus destination for tile-helper GNOME Shell extension
DBUS_DEST="org.gnome.Shell"
DBUS_PATH="/org/gnome/Shell/Extensions/TileHelper"
DBUS_IFACE="org.gnome.Shell.Extensions.TileHelper"

# Parse GNOME work area once (accounts for top panel)
IFS=' ' read -r WA_X WA_Y WA_W WA_H < <(wmctrl -d | head -1 | sed 's/.*WA: \([0-9]*\),\([0-9]*\) \([0-9]*\)x\([0-9]*\).*/\1 \2 \3 \4/')
IFS=$'\n\t'

# Derived work area dimensions
HALF_W=$((WA_W / 2))
HALF_H=$((WA_H / 2))

# Tile window by X11 window ID (synchronous unmaximize + move_resize_frame inside Mutter)
tile_place() {
	local wid="$1" x="$2" y="$3" w="$4" h="$5"
	gdbus call --session -d "$DBUS_DEST" -o "$DBUS_PATH" \
		-m "$DBUS_IFACE.TileXid" "$wid" "$x" "$y" "$w" "$h" >/dev/null 2>&1
}

tile_left() { tile_place "$1" "$WA_X" "$WA_Y" "$HALF_W" "$WA_H"; }
tile_right() { tile_place "$1" "$HALF_W" "$WA_Y" "$HALF_W" "$WA_H"; }

tile_max() {
	local wid="$1"
	gdbus call --session -d "$DBUS_DEST" -o "$DBUS_PATH" \
		-m "$DBUS_IFACE.MaximizeXid" "$wid" >/dev/null 2>&1
}

tile_minimize() {
	local wid="$1"
	gdbus call --session -d "$DBUS_DEST" -o "$DBUS_PATH" \
		-m "$DBUS_IFACE.MinimizeXid" "$wid" >/dev/null 2>&1
}

# Tile by WM_CLASS name (for direct CLI use)
tile_by_class() {
	local class="$1" x="$2" y="$3" w="$4" h="$5"
	gdbus call --session -d "$DBUS_DEST" -o "$DBUS_PATH" \
		-m "$DBUS_IFACE.Tile" "$class" "$x" "$y" "$w" "$h" >/dev/null 2>&1
}

# Animations wrapper
run_layout() {
	gsettings set org.gnome.desktop.interface enable-animations false
	trap 'gsettings set org.gnome.desktop.interface enable-animations true' EXIT
	"$@"
	gsettings set org.gnome.desktop.interface enable-animations true
	trap - EXIT
}

# Get browser window (Firefox or LibreWolf)
get_browser_windows() {
	xdotool search --classname Navigator 2>/dev/null
	xdotool search --classname librewolf 2>/dev/null
}
get_visible_browser_window() {
	xdotool search --onlyvisible --classname Navigator 2>/dev/null | head -n 1
	xdotool search --onlyvisible --classname librewolf 2>/dev/null | head -n 1
}
#}}}

max_alacritty() {
	local window
	window=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)
	if [ -n "$window" ]; then
		tile_max "$window"
	else
		echo "No Alacritty window found."
	fi
}

alacritty_firefox_vertical() {
	local firefox_window alacritty_window
	firefox_window=$(get_browser_windows | head -n 1)
	if [ -z "$firefox_window" ]; then
		echo "No Firefox window found."
		return 1
	fi

	alacritty_window=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)
	if [ -z "$alacritty_window" ]; then
		echo "No Alacritty window found."
		return 1
	fi

	tile_left "$firefox_window"
	tile_right "$alacritty_window"
}

firefox_firefox_vertical() {
	local alacritty_window
	alacritty_window=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)
	if [ -n "$alacritty_window" ]; then
		tile_minimize "$alacritty_window"
	fi

	local firefox_windows
	firefox_windows=($(get_browser_windows | head -n 2))

	if [ ${#firefox_windows[@]} -eq 2 ]; then
		tile_left "${firefox_windows[0]}"
		tile_right "${firefox_windows[1]}"
	elif [ ${#firefox_windows[@]} -eq 1 ]; then
		echo "Only one Firefox window found."
		max_firefox
	else
		echo "No Firefox windows found."
	fi
}

slack_firefox_vertical() {
	local slack firefox_window
	slack=$(xdotool search --onlyvisible --classname Slack | head -n 1)
	if [[ -z "${slack}" ]]; then
		echo "No Slack window found"
		alacritty_firefox_vertical
		exit 0
	fi

	firefox_window=$(get_browser_windows | head -n 1)
	if [ -z "$firefox_window" ]; then
		echo "No browser window found."
		exit 0
	fi

	tile_left "$slack"
	tile_right "$firefox_window"
}

max_firefox() {
	local window
	window=$(get_visible_browser_window | head -n 1)
	if [ -n "$window" ]; then
		tile_max "$window"
	else
		echo "No Firefox window found."
	fi
}

max_slack() {
	local window
	window=$(xdotool search --onlyvisible --classname Slack | head -n 1)
	if [ -n "$window" ]; then
		tile_max "$window"
	else
		echo "No Slack window found."
	fi
}

slack_alacritty_vertical() {
	local slack_window alacritty_window
	slack_window=$(xdotool search --onlyvisible --classname Slack | head -n 1)
	if [[ -z "${slack_window}" ]]; then
		echo "No Slack window found"
		alacritty_firefox_vertical
		exit 0
	fi

	alacritty_window=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)
	if [ -z "$alacritty_window" ]; then
		echo "No Alacritty window found."
		return 1
	fi

	tile_left "$slack_window"
	tile_right "$alacritty_window"
}

firefox_firefox_alacritty() {
	# 3-window layout: 2 browser top, alacritty bottom
	local half_w=$((WA_W / 2))
	local half_h=$((WA_H / 2))
	local bottom_y=$((WA_Y + half_h))

	local firefox_windows alacritty
	firefox_windows=($(get_browser_windows | head -n 2))
	alacritty=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)

	if [ ${#firefox_windows[@]} -eq 2 ] && [ -n "$alacritty" ]; then
		tile_place "${firefox_windows[0]}" "$WA_X" "$WA_Y" "$half_w" "$half_h"
		tile_place "${firefox_windows[1]}" "$half_w" "$WA_Y" "$half_w" "$half_h"
		tile_place "$alacritty" "$WA_X" "$bottom_y" "$WA_W" "$half_h"
	elif [ ${#firefox_windows[@]} -eq 1 ]; then
		echo "Only one Firefox window found."
		alacritty_firefox_vertical
	else
		echo "No Firefox windows found."
	fi
}

alacritty_resize_9_16() {
	local height=2100
	local width=$((height * 9 / 16))

	local window
	window=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)
	if [ -n "$window" ]; then
		tile_place "$window" 50 50 "$width" "$height"
	else
		echo "No Alacritty window found."
	fi
}

slack_browser_alacritty() {
	# 3-window layout: slack left, browser top-right, alacritty bottom-right
	local third_w=$((WA_W / 3))
	local two_third_w=$((WA_W - third_w))
	local half_h=$((WA_H / 2))

	local slack browser alacritty
	slack=$(xdotool search --onlyvisible --classname Slack | head -n 1)
	browser=$(get_visible_browser_window | head -n 1)
	alacritty=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)

	if [[ -n "$slack" && -n "$browser" && -n "$alacritty" ]]; then
		tile_place "$slack" "$WA_X" "$WA_Y" "$third_w" "$WA_H"
		tile_place "$browser" "$third_w" "$WA_Y" "$two_third_w" "$half_h"
		tile_place "$alacritty" "$third_w" "$((WA_Y + half_h))" "$two_third_w" "$half_h"
	else
		echo "Need slack, browser, and alacritty for this layout"
	fi
}

slack_browser_browser() {
	# 3-window layout: slack left, 2 browsers stacked right
	local third_w=$((WA_W / 3))
	local two_third_w=$((WA_W - third_w))
	local half_h=$((WA_H / 2))

	local slack
	slack=$(xdotool search --onlyvisible --classname Slack | head -n 1)
	local browsers
	browsers=($(get_browser_windows | head -n 2))

	if [[ -n "$slack" && ${#browsers[@]} -ge 2 ]]; then
		tile_place "$slack" "$WA_X" "$WA_Y" "$third_w" "$WA_H"
		tile_place "${browsers[0]}" "$third_w" "$WA_Y" "$two_third_w" "$half_h"
		tile_place "${browsers[1]}" "$third_w" "$((WA_Y + half_h))" "$two_third_w" "$half_h"
	else
		echo "Need slack and 2 browsers for this layout"
	fi
}

browser_browser_browser() {
	# 3-window layout: 1 browser left, 2 browsers stacked right (comparison mode)
	local half_w=$((WA_W / 2))
	local half_h=$((WA_H / 2))

	local browsers
	browsers=($(get_browser_windows | head -n 3))

	if [[ ${#browsers[@]} -ge 3 ]]; then
		tile_place "${browsers[0]}" "$WA_X" "$WA_Y" "$half_w" "$WA_H"
		tile_place "${browsers[1]}" "$half_w" "$WA_Y" "$half_w" "$half_h"
		tile_place "${browsers[2]}" "$half_w" "$((WA_Y + half_h))" "$half_w" "$half_h"
	else
		echo "Need 3 browsers for this layout"
	fi
}

browser_browser_alacritty_slack() {
	# 4-window: 2 browsers top, slack bottom-left, alacritty bottom-right
	# Consistent: slack=bottom-left, alacritty=bottom-right (least surprise)
	local half_w=$((WA_W / 2))
	local half_h=$((WA_H / 2))

	local browsers alacritty slack
	browsers=($(get_browser_windows | head -n 2))
	alacritty=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)
	slack=$(xdotool search --onlyvisible --classname Slack | head -n 1)

	if [[ ${#browsers[@]} -ge 2 && -n "$alacritty" && -n "$slack" ]]; then
		tile_place "${browsers[0]}" "$WA_X" "$WA_Y" "$half_w" "$half_h"
		tile_place "${browsers[1]}" "$half_w" "$WA_Y" "$half_w" "$half_h"
		tile_place "$slack" "$WA_X" "$((WA_Y + half_h))" "$half_w" "$half_h"
		tile_place "$alacritty" "$half_w" "$((WA_Y + half_h))" "$half_w" "$half_h"
	else
		echo "Need 2 browsers, alacritty, and slack for this layout"
	fi
}

browser_browser_browser_alacritty() {
	# 4-window: 3 browsers + alacritty (2 top, 2 bottom)
	local half_w=$((WA_W / 2))
	local half_h=$((WA_H / 2))

	local browsers alacritty
	browsers=($(get_browser_windows | head -n 3))
	alacritty=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)

	if [[ ${#browsers[@]} -ge 3 && -n "$alacritty" ]]; then
		tile_place "${browsers[0]}" "$WA_X" "$WA_Y" "$half_w" "$half_h"
		tile_place "${browsers[1]}" "$half_w" "$WA_Y" "$half_w" "$half_h"
		tile_place "${browsers[2]}" "$WA_X" "$((WA_Y + half_h))" "$half_w" "$half_h"
		tile_place "$alacritty" "$half_w" "$((WA_Y + half_h))" "$half_w" "$half_h"
	else
		echo "Need 3 browsers and alacritty for this layout"
	fi
}

chatgpt_alacritty_vertical() {
	local firefox_window alacritty_window
	firefox_window=$(get_browser_windows | head -n 1)

	# PROJECT: brotab
	# Check if ChatGPT tab exists using brotab
	local claude_tab_id=""
	if [ -n "$firefox_window" ]; then
		claude_tab_id=$(brotab list 2>/dev/null | grep "https://chatgpt\.com" | head -n 1 | cut -f1)
	fi

	if [ -n "$claude_tab_id" ]; then
		brotab activate "$claude_tab_id" 2>/dev/null
		xdotool windowactivate "$firefox_window"
	else
		flatpak run io.gitlab.librewolf-community "https://chatgpt.com" 2>/dev/null &
		if [ -z "$firefox_window" ]; then
			sleep 2
			firefox_window=$(get_browser_windows | head -n 1)
		fi
		sleep 0.5
	fi

	if [ -z "$firefox_window" ]; then
		echo "No Firefox window found."
		return 1
	fi

	alacritty_window=$(xdotool search --onlyvisible --classname Alacritty | head -n 1)
	if [ -z "$alacritty_window" ]; then
		echo "No Alacritty window found."
		return 1
	fi

	tile_left "$firefox_window"
	tile_right "$alacritty_window"
}


detach_and_compare() {
	# Called by autokey after it sends Shift+Alt+D to detach tab
	# Just applies the side-by-side layout
	firefox_firefox_vertical
}

reattach_and_max() {
	# Called by autokey after it sends Shift+Alt+A to merge tab
	# Just maximizes the browser
	max_firefox
}

case $1 in
1) run_layout max_alacritty ;;
2) run_layout alacritty_firefox_vertical ;;
3) run_layout firefox_firefox_vertical ;;
4) run_layout slack_firefox_vertical ;;
5) run_layout max_firefox ;;
6) run_layout max_slack ;;
7) run_layout firefox_firefox_alacritty ;;
8) run_layout slack_alacritty_vertical ;;
9) run_layout alacritty_resize_9_16 ;;
10) run_layout chatgpt_alacritty_vertical ;;
11) run_layout slack_browser_alacritty ;;
12) run_layout slack_browser_browser ;;
13) run_layout browser_browser_browser ;;
14) run_layout browser_browser_alacritty_slack ;;
15) run_layout browser_browser_browser_alacritty ;;
16) run_layout detach_and_compare ;;
17) run_layout reattach_and_max ;;
*)
	echo "Usage: $0 {1-17}"
	exit 1
	;;
esac
