#!/usr/bin/env bats

# The pickers reached from a hotkey open one popup window: the normal
# alacritty config, so the per-machine font size applies, overridden to a
# windowed 172x40 and centred on the target screen. Centring needs the pixel
# size of a cell, which the lib derives from the point size in font-size.toml.

setup() {
  LIB="${BATS_TEST_DIRNAME}/../../scripts/__lib_alacritty_popup.sh"
  FONT_FILE="${BATS_TEST_TMPDIR}/font-size.toml"
}

font() {
  printf '[font]\nsize = %s\n' "$1" > "$FONT_FILE"
}

# Run a lib function with alacritty and the screen probes stubbed. alacritty
# prints its arguments, one per line, so a test can read the window it would
# have opened.
popup() {
  local fn="$1" area="$2"; shift 2
  AREA="$area" ALACRITTY_FONT_FILE="$FONT_FILE" bash -c '
    source "'"$LIB"'"
    alacritty() { printf "%s\n" "$@"; }
    get_target_work_area() { [[ -n "$AREA" ]] && printf "%s\n" "$AREA"; [[ -n "$AREA" ]]; }
    xdpyinfo() { printf "  dimensions:    1920x1080 pixels (508x285 millimeters)\n"; }
    export -f alacritty get_target_work_area xdpyinfo
    '"$fn"' "$@"
  ' _ "$@"
}

@test "cell size follows the configured point size" {
  font 19.0
  run popup alacritty_cell_size ""
  [ "$output" = "15 34" ]
}

@test "no font file falls back to the base size" {
  rm -f "$FONT_FILE"
  run popup alacritty_cell_size ""
  [ "$output" = "13 29" ]
}

@test "the popup is windowed at the standard size on the normal config" {
  font 19.0
  run popup alacritty_popup "0 0 3840 2160" bookmarks-popup bash -c main
  [[ "$output" == *"--class"$'\n'"bookmarks-popup"* ]]
  [[ "$output" == *'window.startup_mode="Windowed"'* ]]
  [[ "$output" == *"window.dimensions.columns=172"* ]]
  [[ "$output" == *"window.dimensions.lines=40"* ]]
  [[ "$output" != *"--config-file"* ]]
  [[ "$output" == *"-e"$'\n'"bash"$'\n'"-c"$'\n'"main" ]]
}

@test "the popup is centred on the target work area" {
  font 19.0
  # 172 * 15 + 10 = 2590 wide, 40 * 34 + 10 = 1370 high, inside 3840x2160
  # offset by a panel: x = 0 + (3840 - 2590) / 2, y = 32 + (2128 - 1370) / 2.
  run popup alacritty_popup "0 32 3840 2128" p true
  [[ "$output" == *"window.position.x=625"* ]]
  [[ "$output" == *"window.position.y=411"* ]]
}

@test "a popup wider than the screen pins to the work area origin" {
  font 19.0
  run popup alacritty_popup "100 50 1920 1080" p true
  [[ "$output" == *"window.position.x=100"* ]]
  [[ "$output" == *"window.position.y=50"* ]]
}

@test "the size is overridable per picker" {
  font 19.0
  POPUP_COLUMNS=100 POPUP_LINES=20 run popup alacritty_popup "0 0 3840 2160" p true
  [[ "$output" == *"window.dimensions.columns=100"* ]]
  [[ "$output" == *"window.dimensions.lines=20"* ]]
}

@test "without a work area the whole X screen centres the popup" {
  font 16.0
  # 13x29 cells: 172 * 13 + 10 = 2246 wide, 40 * 29 + 10 = 1170 high, which
  # exceeds 1920x1080, so both coordinates pin to the origin.
  run popup alacritty_popup "" p true
  [[ "$output" == *"window.position.x=0"* ]]
  [[ "$output" == *"window.position.y=0"* ]]
}
