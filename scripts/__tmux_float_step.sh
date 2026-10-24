#!/usr/bin/env bash
set -eo pipefail

# Move a floating tmux pane between the four corners with the arrow keys.
# Left and Right pick the left or right corner and keep the row; Up and Down
# pick the top or bottom corner and keep the column. Snapping to an edge centre
# moved floats along a plus shape and never reached a corner. Centring stays on
# its own key (c).
# Usage: __tmux_float_step.sh left|right|up|down [target-pane]
# A tiled target is left alone.

# float_axis prints low or high for one axis of a float: the half its centre
# is in, the exact middle counting as low. A float on one edge always has its
# centre on that half, so the edges need no separate check.
# Args: start size span, e.g. pane_left pane_width window_width.
float_axis() {
	local start="$1" size="$2" span="$3"
	if (((start + size / 2) * 2 <= span)); then echo low; else echo high; fi
}

# float_target prints the corner one arrow press moves a float to.
# Args: direction pane_left pane_top pane_width pane_height window_width window_height.
float_target() {
	local dir="$1" left="$2" top="$3" width="$4" height="$5" ww="$6" wh="$7"
	local col row
	col=$(float_axis "$left" "$width" "$ww")
	row=$(float_axis "$top" "$height" "$wh")
	case "$dir" in
		left) col=low ;;
		right) col=high ;;
		up) row=low ;;
		down) row=high ;;
		*)
			echo "unknown direction: $dir" >&2
			return 1
			;;
	esac
	if [[ "$row" == low ]]; then row=top; else row=bottom; fi
	if [[ "$col" == low ]]; then col=left; else col=right; fi
	echo "$row-$col"
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
