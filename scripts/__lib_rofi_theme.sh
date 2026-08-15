#!/usr/bin/env bash
# Shared rofi look for every global picker (value, layout, secret, snippet, ;;?).
#
# The same Dracula block was pasted into five scripts, each with its own width
# and line count. Retuning meant five edits, so in practice it meant none, and
# the sizes drifted apart: 400px to 1200px, 6 lines to 12. Two of those had
# already been caught truncating real rows (see the 900px note in
# __secret_picker.sh). This is that block, once.
#
# Usage:
#   source "${script_dir}/__lib_rofi_theme.sh"
#   rofi_theme [width_px] [lines]
#   rofi -dmenu -i -p prompt "${ROFI_THEME[@]}"
#
# Callers may append their own -theme-str after "${ROFI_THEME[@]}"; rofi applies
# them in order, so a later rule wins for the properties it names and leaves the
# rest of the base intact. That is how __snippet_picker.sh keeps its multi-line
# row rules without restating the palette.
#
# Sized for a 3840x2160 display. Override per machine without touching callers:
#   ROFI_PICKER_WIDTH, ROFI_PICKER_LINES, ROFI_PICKER_FONT, ROFI_PICKER_FONT_SIZE

rofi_theme() {
	local width="${1:-${ROFI_PICKER_WIDTH:-1600}}"
	local lines="${2:-${ROFI_PICKER_LINES:-18}}"
	local font="${ROFI_PICKER_FONT:-JetBrainsMono Nerd Font}"
	local size="${ROFI_PICKER_FONT_SIZE:-14}"

	# shellcheck disable=SC2034  # read by the sourcing script, not here
	ROFI_THEME=(
		-theme-str "* {font: \"${font} ${size}\";}"
		-theme-str "window {width: ${width}px; background-color: argb:ff282a36; border: 2px solid; border-color: argb:ffbd93f9; border-radius: 8px;}"
		-theme-str 'mainbox {background-color: transparent;}'
		-theme-str 'inputbar {background-color: argb:ff44475a; text-color: argb:fff8f8f2; padding: 8px;}'
		-theme-str 'prompt {text-color: argb:ffbd93f9;}'
		-theme-str 'entry {text-color: argb:fff8f8f2;}'
		-theme-str "listview {background-color: transparent; lines: ${lines};}"
		-theme-str 'element {padding: 8px; background-color: transparent; text-color: argb:fff8f8f2;}'
		-theme-str 'element.selected {background-color: argb:ff44475a; text-color: argb:ff50fa7b;}'
	)
}
