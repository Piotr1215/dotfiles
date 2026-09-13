#!/usr/bin/env bats

# One font size in alacritty.toml fits one desk: 16pt is right on the 4k
# screen at home and oversized on a 24" 1080p panel. The script derives the
# size from the main screen's pixel pitch and writes the import alacritty.toml
# loads, so every desk gets the same glyph height without editing config.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__alacritty_font_scale.sh"
  FONT_FILE="${BATS_TEST_TMPDIR}/font-size.toml"
}

# Run the script with xrandr, wmctrl and xrdb stubbed.
scale() {
  local xr="$1" dpi="$2"; shift 2
  XR="$xr" DPI="$dpi" ALACRITTY_FONT_FILE="$FONT_FILE" bash -c '
    xrandr() { [[ -n "$XR" ]] && printf "%b\n" "$XR"; return 0; }
    wmctrl() { return 0; }
    xrdb() { [[ -n "$DPI" ]] && printf "Xft.dpi:\t%s\n" "$DPI"; return 0; }
    export -f xrandr wmctrl xrdb
    "'"$SCRIPT"'" "$@"
  ' _ "$@"
}

XR_1080P='HDMI-0 connected primary 1920x1080+2560+0 (normal left inverted right x axis y axis) 476mm x 267mm\neDP-1-1 connected 2560x1600+0+0 (normal) 345mm x 215mm'
XR_4K_32='DP-2 connected primary 3840x2160+0+0 (normal left inverted right x axis y axis) 774mm x 435mm'
XR_NO_MM='HDMI-1 connected primary 1920x1080+0+0 (normal) 0mm x 0mm'

@test "24 inch 1080p at 96 dpi gets 14pt" {
  run scale "$XR_1080P" 96 --print
  [ "$status" -eq 0 ]
  [ "$output" = "14.0" ]
}

@test "34 inch 4k at 96 dpi gets 17pt" {
  run scale "$XR_4K_32" 96 --print
  [ "$output" = "17.0" ]
}

@test "200 percent scaling halves the point size for the same glyph height" {
  run scale "$XR_4K_32" 192 --print
  [ "$output" = "8.5" ]
}

@test "target height is tunable through the environment" {
  ALACRITTY_FONT_MM=5.0 run scale "$XR_1080P" 96 --print
  [ "$output" = "15.0" ]
}

@test "no physical size falls back to the base size" {
  run scale "$XR_NO_MM" 96 --print
  [ "$output" = "16.0" ]
  ALACRITTY_FONT_BASE=14.0 run scale "$XR_NO_MM" 96 --print
  [ "$output" = "14.0" ]
}

@test "no xrandr at all falls back to the base size" {
  run scale "" "" --print
  [ "$output" = "16.0" ]
}

@test "writes the import file and leaves it untouched when unchanged" {
  run scale "$XR_1080P" 96
  [ "$status" -eq 0 ]
  grep -q '^size = 14.0$' "$FONT_FILE"
  grep -q '^\[font\]$' "$FONT_FILE"
  touch -d '2000-01-01' "$FONT_FILE"
  run scale "$XR_1080P" 96
  [ "$(date -r "$FONT_FILE" +%Y)" = "2000" ]
}

@test "a desk change rewrites the file" {
  run scale "$XR_1080P" 96
  run scale "$XR_4K_32" 96
  grep -q '^size = 17.0$' "$FONT_FILE"
}

@test "alacritty.toml imports the generated file and carries no font size of its own" {
  local toml="${BATS_TEST_DIRNAME}/../../.config/alacritty/alacritty.toml"
  grep -q 'font-size.toml' "$toml"
  run grep -cE '^size = ' "$toml"
  [ "$output" -eq 0 ]
}
