#!/usr/bin/env bash

# Centred Alacritty popup for the fzf pickers reached from a global hotkey.
#
# The pickers used to open alacritty with --config-file /dev/null, which
# sidestepped the Maximized startup mode in alacritty.toml and with it the
# per-machine font size and the theme: 11pt on a 4k screen, unreadable. The
# popup now runs on the normal config and overrides the one thing it must,
# the window mode and size.
#
# Alacritty sizes a window in cells, and the cell follows the font, so the
# pixel size needed to centre the window is derived from the point size
# font-size.toml holds. JetBrains Mono advances 0.6em and sets a 1.34em line;
# at the 96 dpi alacritty assumes on X11 that is 0.8 and 1.79 px per point.
# Measured 15x34 px at 19pt. A pixel out shifts the window, never the content.
#
# One size for every picker, so the link picker and the bindings help open
# as the same window and a new picker gets the same look by calling this.
#
# Functions:
#   alacritty_cell_size           print "width height" of one cell in px
#   alacritty_popup CLASS CMD...  open the popup and wait for it
#
# Env:
#   ALACRITTY_FONT_FILE   the font import (default ~/.config/alacritty/font-size.toml)
#   POPUP_COLUMNS         width in cells (default 172)
#   POPUP_LINES           height in cells (default 40)

# shellcheck source=scripts/__lib_screen.sh
source "$(dirname "${BASH_SOURCE[0]}")/__lib_screen.sh"

ALACRITTY_FONT_FILE="${ALACRITTY_FONT_FILE:-$HOME/.config/alacritty/font-size.toml}"
POPUP_COLUMNS="${POPUP_COLUMNS:-172}"
POPUP_LINES="${POPUP_LINES:-40}"
# window.padding in alacritty.toml, each side.
ALACRITTY_PADDING=5
ALACRITTY_BASE_PT=16

alacritty_font_pt() {
	local pt
	pt=$(awk -F'=' '/^size/ { gsub(/ /, "", $2); print $2 }' "$ALACRITTY_FONT_FILE" 2>/dev/null)
	printf '%s\n' "${pt:-$ALACRITTY_BASE_PT}"
}

alacritty_cell_size() {
	awk -v pt="$(alacritty_font_pt)" 'BEGIN { printf "%d %d\n", pt * 0.8 + 0.5, pt * 1.79 + 0.5 }'
}

# Centred on the target monitor's work area, so a laptop beside an external
# screen gets the popup on the screen in use rather than across both. Falls
# back to the whole X screen when nothing reports a work area.
alacritty_popup() {
	local class="$1" columns="$POPUP_COLUMNS" lines="$POPUP_LINES"
	shift
	local cell_w cell_h area_x area_y area_w area_h win_w win_h pos_x pos_y
	read -r cell_w cell_h < <(alacritty_cell_size)
	if ! IFS=' ' read -r area_x area_y area_w area_h < <(get_target_work_area); then
		area_x=0
		area_y=0
		read -r area_w area_h < <(xdpyinfo | awk '/dimensions:/ { print $2 }' | tr 'x' ' ')
	fi
	win_w=$((columns * cell_w + 2 * ALACRITTY_PADDING))
	win_h=$((lines * cell_h + 2 * ALACRITTY_PADDING))
	pos_x=$((area_x + (area_w - win_w) / 2))
	pos_y=$((area_y + (area_h - win_h) / 2))
	((pos_x < area_x)) && pos_x=$area_x
	((pos_y < area_y)) && pos_y=$area_y

	alacritty --class "$class" \
		-o 'window.startup_mode="Windowed"' \
		-o "window.dimensions.columns=$columns" \
		-o "window.dimensions.lines=$lines" \
		-o "window.position.x=$pos_x" \
		-o "window.position.y=$pos_y" \
		-e "$@"
}
