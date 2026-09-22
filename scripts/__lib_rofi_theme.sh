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
#   rofi_theme [max_width_px] [lines] [row_height]
#   rofi -dmenu -i -p prompt "${ROFI_THEME[@]}"
#
# Callers may append their own -theme-str after "${ROFI_THEME[@]}"; rofi applies
# them in order, so a later rule wins for the properties it names and leaves the
# rest of the base intact. That is how __snippet_picker.sh keeps its multi-line
# row rules without restating the palette.
#
# Width and height follow rofi's target monitor. Width stops at the caller's
# pixel limit. Height stays natural for short menus and caps long menus by
# reducing their visible row count.
# Override the defaults per machine without touching callers:
#   ROFI_PICKER_WIDTH, ROFI_PICKER_LINES, ROFI_PICKER_FONT,
#   ROFI_PICKER_FONT_SIZE, ROFI_PICKER_MONITOR_HEIGHT

# Print the height of the monitor under the pointer. The environment override
# keeps the calculation usable in tests and sessions without XRandR.
rofi_monitor_height() {
	local mouse_x="" mouse_y="" key value line monitor_w monitor_h monitor_x monitor_y hypr_height
	if [[ "${ROFI_PICKER_MONITOR_HEIGHT:-}" =~ ^[0-9]+$ ]]; then
		printf '%s\n' "$ROFI_PICKER_MONITOR_HEIGHT"
		return 0
	fi
	if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && command -v hyprctl >/dev/null 2>&1 &&
		command -v jq >/dev/null 2>&1; then
		hypr_height=$(hyprctl -j monitors 2>/dev/null |
			jq -er 'first(.[] | select(.focused)) | ((.height / (.scale // 1)) | floor)' 2>/dev/null) || hypr_height=""
		if [[ "$hypr_height" =~ ^[0-9]+$ ]]; then
			printf '%s\n' "$hypr_height"
			return 0
		fi
	fi
	command -v xdotool >/dev/null 2>&1 || return 1
	command -v xrandr >/dev/null 2>&1 || return 1
	while IFS='=' read -r key value; do
		case "$key" in
			X) mouse_x="$value" ;;
			Y) mouse_y="$value" ;;
		esac
	done < <(xdotool getmouselocation --shell 2>/dev/null)
	[[ "$mouse_x" =~ ^-?[0-9]+$ && "$mouse_y" =~ ^-?[0-9]+$ ]] || return 1

	while IFS= read -r line; do
		[[ "$line" == *" connected "* ]] || continue
		[[ "$line" =~ ([0-9]+)x([0-9]+)([+-][0-9]+)([+-][0-9]+) ]] || continue
		monitor_w="${BASH_REMATCH[1]}"
		monitor_h="${BASH_REMATCH[2]}"
		monitor_x="${BASH_REMATCH[3]}"
		monitor_y="${BASH_REMATCH[4]}"
		if ((mouse_x >= monitor_x && mouse_x < monitor_x + monitor_w &&
			mouse_y >= monitor_y && mouse_y < monitor_y + monitor_h)); then
			printf '%s\n' "$monitor_h"
			return 0
		fi
	done < <(xrandr --current 2>/dev/null)
	return 1
}

rofi_theme() {
	local width="${1:-${ROFI_PICKER_WIDTH:-1600}}"
	local lines="${2:-${ROFI_PICKER_LINES:-18}}"
	local row_height="${3:-1}"
	local font="${ROFI_PICKER_FONT:-JetBrainsMono Nerd Font}"
	local size="${ROFI_PICKER_FONT_SIZE:-14}"
	local monitor_height usable_height row_pixels max_lines

	# Rofi has no working max-height property. Reserve 80px for the input and
	# message, then cap visible rows within 80% of the monitor. fixed-height is
	# false by default, so menus with fewer items still shrink to their content.
	if [[ "$lines" =~ ^[0-9]+$ && "$row_height" =~ ^[0-9]+$ && "$size" =~ ^[0-9]+$ ]] &&
		((row_height > 0)) && monitor_height=$(rofi_monitor_height); then
		usable_height=$((monitor_height * 80 / 100 - 80))
		row_pixels=$((size * 2 * row_height + 18))
		max_lines=$((usable_height / row_pixels))
		((max_lines < 3)) && max_lines=3
		((lines > max_lines)) && lines="$max_lines"
	fi

	# shellcheck disable=SC2034  # read by the sourcing script, not here
	ROFI_THEME=(
		-theme-str "* {font: \"${font} ${size}\";}"
		-theme-str "window {width: calc(80% min ${width}px); background-color: argb:ff282a36; border: 2px solid; border-color: argb:ffbd93f9; border-radius: 8px;}"
		-theme-str 'mainbox {background-color: transparent;}'
		-theme-str 'inputbar {background-color: argb:ff44475a; text-color: argb:fff8f8f2; padding: 8px;}'
		-theme-str 'prompt {text-color: argb:ffbd93f9;}'
		-theme-str 'entry {text-color: argb:fff8f8f2;}'
		# The -mesg box: stock rofi draws it in the default dark foreground on this
		# dark window, so every hint line any picker advertises was unreadable. The
		# row text is drawn by element-text, not textbox, so setting textbox here
		# styles the message without touching the list.
		-theme-str 'message {background-color: argb:ff44475a; padding: 8px; border-radius: 4px;}'
		-theme-str 'textbox {background-color: transparent; text-color: argb:fff8f8f2;}'
		-theme-str "listview {background-color: transparent; lines: ${lines};}"
		-theme-str 'element {padding: 8px; background-color: transparent; text-color: argb:fff8f8f2;}'
		-theme-str 'element.selected {background-color: argb:ff44475a; text-color: argb:ff50fa7b;}'
	)
}
