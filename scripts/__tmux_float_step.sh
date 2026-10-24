#!/usr/bin/env bash
set -eo pipefail

# Step a floating tmux pane one cell across the 3x3 grid of move-pane -P
# positions. Each arrow keeps the other axis: Left from top-centre lands on
# top-left, so corners are two presses away. Snapping straight to an edge
# centre moved floats along a plus shape and never reached a corner.
# Usage: __tmux_float_step.sh left|right|up|down [target-pane]
# A tiled target is left alone.

# float_axis prints low, mid or high for one axis of a float.
# A float touching exactly one edge sits at that edge. One touching both, or
# neither, is placed by its centre: the first third is low, the last high.
# Args: start size span, e.g. pane_left pane_width window_width.
float_axis() {
	local start="$1" size="$2" span="$3"
	local end=$((start + size)) low=0 high=0 centre
	if ((start <= 2)); then low=1; fi
	if ((end >= span - 2)); then high=1; fi
	if ((low != high)); then
		if ((low)); then echo low; else echo high; fi
		return 0
	fi
	if ((low)); then
		echo mid
		return 0
	fi
	centre=$((start + size / 2))
	if ((centre * 3 < span)); then
		echo low
	elif ((centre * 3 > 2 * span)); then
		echo high
	else
		echo mid
	fi
}

# axis_step moves one axis value a cell toward low or high, stopping at the edge.
# Args: value (low|mid|high) toward (low|high).
axis_step() {
	local value="$1" toward="$2"
	if [[ "$toward" == low ]]; then
		if [[ "$value" == high ]]; then echo mid; else echo low; fi
	else
		if [[ "$value" == low ]]; then echo mid; else echo high; fi
	fi
}

# float_target prints the move-pane -P position one step from a float's cell.
# Args: direction pane_left pane_top pane_width pane_height window_width window_height.
float_target() {
	local dir="$1" left="$2" top="$3" width="$4" height="$5" ww="$6" wh="$7"
	local col row name_row name_col
	col=$(float_axis "$left" "$width" "$ww")
	row=$(float_axis "$top" "$height" "$wh")
	case "$dir" in
		left) col=$(axis_step "$col" low) ;;
		right) col=$(axis_step "$col" high) ;;
		up) row=$(axis_step "$row" low) ;;
		down) row=$(axis_step "$row" high) ;;
		*)
			echo "unknown direction: $dir" >&2
			return 1
			;;
	esac
	case "$row" in low) name_row=top ;; mid) name_row=centre ;; high) name_row=bottom ;; esac
	case "$col" in low) name_col=left ;; mid) name_col=centre ;; high) name_col=right ;; esac
	if [[ "$name_row" == centre && "$name_col" == centre ]]; then
		echo centre
	else
		echo "$name_row-$name_col"
	fi
}

# main reads the target pane's geometry and moves it if it is a float.
main() {
	local dir="${1:-}" target="${2:-}" geo floating left top width height ww wh pos
	local args=()
	case "$dir" in
		left | right | up | down) ;;
		*)
			echo "usage: ${0##*/} left|right|up|down [target-pane]" >&2
			exit 1
			;;
	esac
	if [[ -n "$target" ]]; then args=(-t "$target"); fi
	geo=$(tmux display-message -p "${args[@]}" \
		'#{pane_floating_flag} #{pane_left} #{pane_top} #{pane_width} #{pane_height} #{window_width} #{window_height}')
	read -r floating left top width height ww wh <<<"$geo"
	if [[ "$floating" != 1 ]]; then exit 0; fi
	pos=$(float_target "$dir" "$left" "$top" "$width" "$height" "$ww" "$wh")
	tmux move-pane "${args[@]}" -P "$pos"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	main "$@"
fi
