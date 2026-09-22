#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	THEME="$REPO_ROOT/scripts/__lib_rofi_theme.sh"
	WRAPPER="$REPO_ROOT/scripts/__rofi.sh"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$STUB_BIN"
}

@test "picker width follows the monitor and keeps the caller's pixel cap" {
	run bash -c '
		source "$1"
		rofi_theme 2000
		printf "%s\n" "${ROFI_THEME[@]}"
	' _ "$THEME"

	[ "$status" -eq 0 ]
	[[ "$output" == *"window {width: calc(80% min 2000px);"* ]]
}

@test "default picker width uses the same responsive rule" {
	run bash -c '
		source "$1"
		rofi_theme
		printf "%s\n" "${ROFI_THEME[@]}"
	' _ "$THEME"

	[ "$status" -eq 0 ]
	[[ "$output" == *"window {width: calc(80% min 1600px);"* ]]
}

@test "single-line menus cap their rows within 80 percent of the monitor" {
	run env ROFI_PICKER_MONITOR_HEIGHT=1080 bash -c '
		source "$1"
		rofi_theme 1800 26
		printf "%s\n" "${ROFI_THEME[@]}"
	' _ "$THEME"

	[ "$status" -eq 0 ]
	[[ "$output" == *"listview {background-color: transparent; lines: 17;}"* ]]
}

@test "short menus keep their natural row limit" {
	run env ROFI_PICKER_MONITOR_HEIGHT=1080 bash -c '
		source "$1"
		rofi_theme 900 10
		printf "%s\n" "${ROFI_THEME[@]}"
	' _ "$THEME"

	[ "$status" -eq 0 ]
	[[ "$output" == *"listview {background-color: transparent; lines: 10;}"* ]]
}

@test "multi-line menus include row height in the monitor cap" {
	run env ROFI_PICKER_MONITOR_HEIGHT=1080 bash -c '
		source "$1"
		rofi_theme 1600 18 4
		printf "%s\n" "${ROFI_THEME[@]}"
	' _ "$THEME"

	[ "$status" -eq 0 ]
	[[ "$output" == *"listview {background-color: transparent; lines: 6;}"* ]]
}

@test "Hyprland monitor height accounts for display scale" {
	cat > "$STUB_BIN/hyprctl" <<-'STUB'
		#!/usr/bin/env bash
		printf '%s\n' '[{"height":2160,"scale":1.5,"focused":true}]'
	STUB
	chmod +x "$STUB_BIN/hyprctl"

	run env HYPRLAND_INSTANCE_SIGNATURE=test PATH="$STUB_BIN:$PATH" bash -c '
		source "$1"
		rofi_monitor_height
	' _ "$THEME"

	[ "$status" -eq 0 ]
	[ "$output" = "1440" ]
}

@test "direct rofi modes receive the shared responsive theme" {
	cat > "$STUB_BIN/rofi" <<-'STUB'
		#!/usr/bin/env bash
		printf '%s\n' "$@"
	STUB
	chmod +x "$STUB_BIN/rofi"

	run env PATH="$STUB_BIN:$PATH" ROFI_PICKER_MONITOR_HEIGHT=1080 \
		"$WRAPPER" -show drun -show-icons

	[ "$status" -eq 0 ]
	[[ "$output" == *"window {width: calc(80% min 1600px);"* ]]
	[[ "$output" == *"listview {background-color: transparent; lines: 17;}"* ]]
}

@test "Hyprland direct rofi bindings use the shared wrapper" {
	run grep -F 'exec, ~/dev/dotfiles/scripts/__rofi.sh -show drun -show-icons' \
		"$REPO_ROOT/.config/hypr/hyprland.conf"
	[ "$status" -eq 0 ]

	run grep -F '| ~/dev/dotfiles/scripts/__rofi.sh -dmenu -p "Clipboard" |' \
		"$REPO_ROOT/.config/hypr/hyprland.conf"
	[ "$status" -eq 0 ]
}
