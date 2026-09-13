#!/usr/bin/env bash
set -eo pipefail

# PROJECT: window_manager
# Cycle the focused window through full, left half and a floating square a third
# of the screen wide, one step per press (Super+Shift+R).
#
# __layouts.sh arranges named apps on the main screen. This acts on whatever has
# focus and keeps it on its own screen, which is what a browser or Zoom window
# being shuffled by hand needs.
#
# The next step is read off the window, not a state file, so a window resized or
# maximized by hand still steps sensibly:
#   maximized             -> left half
#   about half the width  -> square third
#   anything else         -> full

# shellcheck source=scripts/__lib_screen.sh
source "$(dirname "${BASH_SOURCE[0]}")/__lib_screen.sh"

# Gap between the square and the left screen edge, so it reads as floating.
EDGE_GAP=40

DBUS_DEST="org.gnome.Shell"
DBUS_PATH="/org/gnome/Shell/Extensions/TileHelper"
DBUS_IFACE="org.gnome.Shell.Extensions.TileHelper"

# Call a tile-helper method: synchronous inside Mutter, same path __layouts.sh uses.
tile_helper() {
	gdbus call --session -d "$DBUS_DEST" -o "$DBUS_PATH" -m "$DBUS_IFACE.$1" "${@:2}" >/dev/null
}

# Print the connected xrandr output whose rectangle holds the point X Y.
monitor_at() {
	local px="$1" py="$2" line geom w h x y
	while IFS= read -r line; do
		[[ "$line" == *" connected "* ]] || continue
		geom=$(grep -oE '[0-9]+x[0-9]+\+[0-9]+\+[0-9]+' <<<"$line" | head -n 1)
		[[ -n "$geom" ]] || continue
		IFS='x+' read -r w h x y <<<"$geom"
		if (( px >= x && px < x + w && py >= y && py < y + h )); then
			printf '%s\n' "${line%% *}"
			return 0
		fi
	done < <(xrandr --current 2>/dev/null)
	return 1
}

# Print full, half or third: the step after the window's current shape.
next_step() {
	local state="$1" win_w="$2" area_w="$3"
	if [[ "$state" == *_NET_WM_STATE_MAXIMIZED_HORZ* && "$state" == *_NET_WM_STATE_MAXIMIZED_VERT* ]]; then
		echo half
	elif (( win_w * 100 >= area_w * 45 && win_w * 100 <= area_w * 55 )); then
		echo third
	else
		echo full
	fi
}

main() {
	local wid key value win_x="" win_y="" win_w="" win_h="" mon ax ay aw ah side
	wid=$(xdotool getactivewindow)
	while IFS='=' read -r key value; do
		case "$key" in
		X) win_x="$value" ;;
		Y) win_y="$value" ;;
		WIDTH) win_w="$value" ;;
		HEIGHT) win_h="$value" ;;
		esac
	done < <(xdotool getwindowgeometry --shell "$wid")
	if [[ -z "$win_w" ]]; then
		echo "Cannot read geometry of window $wid." >&2
		exit 1
	fi

	# The screen holding the window's centre, not the primary: a window on the
	# laptop screen cycles there.
	mon=$(monitor_at $((win_x + win_w / 2)) $((win_y + win_h / 2))) || mon=""
	IFS=' ' read -r ax ay aw ah < <(LAYOUT_MONITOR="$mon" get_target_work_area)
	if [[ -z "${aw:-}" ]]; then
		echo "Cannot determine screen work area (xrandr/wmctrl)." >&2
		exit 1
	fi

	case "$(next_step "$(xprop -id "$wid" _NET_WM_STATE)" "$win_w" "$aw")" in
	full) tile_helper MaximizeXid "$wid" ;;
	half) tile_helper TileXid "$wid" "$ax" "$ay" $((aw / 2)) "$ah" ;;
	third)
		# A square, not a column: the window's resting form for reading, dragged
		# around by hand and snapped back here. Capped at the screen height so a
		# very wide screen still fits it.
		side=$((aw / 3))
		if ((side > ah)); then side=$ah; fi
		tile_helper TileXid "$wid" $((ax + EDGE_GAP)) $((ay + (ah - side) / 2)) "$side" "$side"
		;;
	esac
}

main "$@"
