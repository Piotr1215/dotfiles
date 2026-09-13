#!/usr/bin/env bash

# PROJECT: window_manager
# Screen geometry helpers for window layout scripts.
#
# _NET_WORKAREA (wmctrl -d) is the bounding box of every monitor minus panel
# struts, so on a multi-monitor desk a layout computed from it spans all
# screens. Layouts should target one screen: the xrandr primary output, or the
# output named in LAYOUT_MONITOR. The work area of that screen is its xrandr
# rectangle clipped to _NET_WORKAREA, which removes the top panel when the panel
# sits on that screen. All values are physical X11 pixels.
#
# Always `xrandr --current`, never a bare `xrandr` or `--query`: those re-probe
# every output (EDID over DDC, 100-190ms measured on the NVIDIA desk) inside
# the X server, and the one-second argos applets calling this lib stalled the
# whole desktop with it (2026-09-13, "system feels sluggish"). --current
# returns the server's cached configuration in under a millisecond.

# Print "name WxH+X+Y" for the target monitor: LAYOUT_MONITOR if set and
# connected, else the primary, else the first connected output.
get_target_monitor() {
	local want="${LAYOUT_MONITOR:-}" line name geom primary="" first=""
	while IFS= read -r line; do
		[[ "$line" == *" connected "* ]] || continue
		name="${line%% *}"
		geom=$(grep -oE '[0-9]+x[0-9]+\+[0-9]+\+[0-9]+' <<<"$line" | head -n 1)
		[[ -n "$geom" ]] || continue
		[[ -n "$want" && "$name" == "$want" ]] && { printf '%s %s\n' "$name" "$geom"; return 0; }
		[[ -z "$primary" && "$line" == *" primary "* ]] && primary="$name $geom"
		[[ -z "$first" ]] && first="$name $geom"
	done < <(xrandr --current 2>/dev/null)
	if [[ -n "$primary" ]]; then
		printf '%s\n' "$primary"
	elif [[ -n "$first" ]]; then
		printf '%s\n' "$first"
	else
		return 1
	fi
}

# Print "name WxH+X+Y" for the first connected output that is not the target
# monitor: the laptop panel beside the external screen. Fails on a single
# screen desk, which callers treat as "no second screen" rather than an error.
get_secondary_monitor() {
	local target line name geom
	target=$(get_target_monitor) || return 1
	target="${target%% *}"
	while IFS= read -r line; do
		[[ "$line" == *" connected "* ]] || continue
		name="${line%% *}"
		[[ "$name" == "$target" ]] && continue
		geom=$(grep -oE '[0-9]+x[0-9]+\+[0-9]+\+[0-9]+' <<<"$line" | head -n 1)
		[[ -n "$geom" ]] || continue
		printf '%s %s\n' "$name" "$geom"
		return 0
	done < <(xrandr --current 2>/dev/null)
	return 1
}

# Print "X Y W H" of _NET_WORKAREA for the current desktop.
get_net_workarea() {
	wmctrl -d 2>/dev/null | awk '$2 == "*" || NR == 1 { wa = $0; if ($2 == "*") exit } END {
		if (match(wa, /WA: [0-9]+,[0-9]+ [0-9]+x[0-9]+/)) {
			s = substr(wa, RSTART + 4, RLENGTH - 4)
			gsub(/[,x]/, " ", s)
			print s
		}
	}'
}

# Print "X Y W H": the target monitor clipped to _NET_WORKAREA. Falls back to
# the full _NET_WORKAREA when xrandr reports nothing, and to the raw monitor
# when wmctrl reports nothing.
get_target_work_area() {
	local mon geom mw mh mx my wx wy ww wh x1 y1 x2 y2
	mon=$(get_target_monitor) || mon=""
	IFS=' ' read -r wx wy ww wh < <(get_net_workarea)

	if [[ -z "$mon" ]]; then
		[[ -n "${wx:-}" ]] || return 1
		printf '%s %s %s %s\n' "$wx" "$wy" "$ww" "$wh"
		return 0
	fi

	geom="${mon#* }"
	mw="${geom%%x*}"; geom="${geom#*x}"
	mh="${geom%%+*}"; geom="${geom#*+}"
	mx="${geom%%+*}"; my="${geom#*+}"

	if [[ -z "${wx:-}" ]]; then
		printf '%s %s %s %s\n' "$mx" "$my" "$mw" "$mh"
		return 0
	fi

	x1=$(( mx > wx ? mx : wx ))
	y1=$(( my > wy ? my : wy ))
	x2=$(( mx + mw < wx + ww ? mx + mw : wx + ww ))
	y2=$(( my + mh < wy + wh ? my + mh : wy + wh ))
	if (( x2 <= x1 || y2 <= y1 )); then
		printf '%s %s %s %s\n' "$mx" "$my" "$mw" "$mh"
		return 0
	fi
	printf '%s %s %s %s\n' "$x1" "$y1" "$((x2 - x1))" "$((y2 - y1))"
}

# Print the physical millimetres per pixel of an output (from the "WxH" and
# "476mm x 267mm" fields of its xrandr line). Fails when xrandr reports no
# physical size (projectors, VMs), so callers can keep a base value.
get_monitor_mm_per_px() {
	local name="$1" line px mm
	line=$(xrandr --current 2>/dev/null | grep -E "^${name} connected " | head -n 1)
	[[ -n "$line" ]] || return 1
	px=$(grep -oE '[0-9]+x[0-9]+\+[0-9]+\+[0-9]+' <<<"$line" | head -n 1)
	px="${px%%x*}"
	mm=$(grep -oE '[0-9]+mm x [0-9]+mm' <<<"$line" | head -n 1)
	mm="${mm%%mm*}"
	[[ -n "$px" && -n "$mm" && "$px" -gt 0 && "$mm" -gt 0 ]] || return 1
	awk -v mm="$mm" -v px="$px" 'BEGIN { printf "%.5f\n", mm / px }'
}

# Succeed when the main screen is narrow enough that the top panel overflows
# and GNOME truncates every indicator to an ellipsis. Argos labels use this to
# pick a compact form. PANEL_COMPACT_BELOW is the width in pixels (default
# 2560), so a single 4k screen keeps the full labels.
panel_compact() {
	local mon geom w
	mon=$(get_target_monitor) || return 1
	geom="${mon#* }"
	w="${geom%%x*}"
	[[ "$w" -lt "${PANEL_COMPACT_BELOW:-2560}" ]]
}

# Print the Pango size an argos panel label should use: the given size on a
# wide main screen, two points smaller on a narrow one. The panel renders a
# label that holds no Latin letter (an emoji plus digits, or digits alone)
# about 20 percent larger than a label with one at the same size, emoji or
# not, visible letter or not (measured with minimal pairs on the panel,
# 2026-09-13; pango-view renders them equal, so this is GNOME Shell's doing).
# Pass "letterless" as the second argument and the size is scaled by 0.85 so
# the digits line up with the lettered labels.
panel_label_size() {
	local normal="${1:-12}" kind="${2:-}" size
	if panel_compact; then
		size=$((normal - 2))
	else
		size=$normal
	fi
	if [[ "$kind" == "letterless" ]]; then
		awk -v s="$size" 'BEGIN { printf "%.1f\n", s * 0.85 }'
	else
		printf '%s\n' "$size"
	fi
}
