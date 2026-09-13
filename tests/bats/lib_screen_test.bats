#!/usr/bin/env bats

# _NET_WORKAREA is the bounding box of every monitor, so a layout computed from
# it spans a laptop panel and the external monitor beside it. The lib resolves
# one target screen (xrandr primary, or LAYOUT_MONITOR) and clips it to the
# work area. The home desk is a single 4k screen, the laptop desk is the
# exception, and both must produce the right rectangle without configuration.

setup() {
  LIB="${BATS_TEST_DIRNAME}/../../scripts/__lib_screen.sh"
}

# Run a lib function with xrandr and wmctrl stubbed. IFS is set the way
# __layouts.sh sets it, since that is what broke the first version.
wa() {
  local fn="$1" xr="$2" wm="$3"
  XR="$xr" WM="$wm" bash -c '
    IFS=$'"'"'\n\t'"'"'
    source "'"$LIB"'"
    xrandr() { [[ -n "$XR" ]] && printf "%b\n" "$XR"; return 0; }
    wmctrl() { [[ -n "$WM" ]] && printf "%b\n" "$WM"; return 0; }
    export -f xrandr wmctrl
    '"$fn"'
  '
}

XR_LAPTOP='Screen 0: minimum 8 x 8, current 4480 x 1600\nHDMI-0 connected primary 1920x1080+2560+0 (normal left inverted right x axis y axis) 476mm x 267mm\n   1920x1080     60.00*+\neDP-1-1 connected 2560x1600+0+0 (normal left inverted right x axis y axis) 345mm x 215mm\n   2560x1600    240.00*+\nDP-0 disconnected (normal left inverted right x axis y axis)'
WM_LAPTOP='0  * DG: 4480x1600  VP: 0,0  WA: 0,32 4480x1568  Workspace 1\n1  - DG: 4480x1600  VP: N/A  WA: 0,32 4480x1568  '

XR_4K='Screen 0: minimum 8 x 8, current 3840 x 2160\nDP-2 connected primary 3840x2160+0+0 (normal left inverted right x axis y axis) 600mm x 340mm\n   3840x2160     60.00*+'
WM_4K='0  * DG: 3840x2160  VP: 0,0  WA: 0,64 3840x2096  Workspace 1'

@test "single 4k screen: work area is the whole screen minus the panel" {
  run wa get_target_work_area "$XR_4K" "$WM_4K"
  [ "$status" -eq 0 ]
  [ "$output" = "0 64 3840 2096" ]
}

@test "laptop beside primary: work area is the primary only, panel clipped" {
  run wa get_target_work_area "$XR_LAPTOP" "$WM_LAPTOP"
  [ "$status" -eq 0 ]
  [ "$output" = "2560 32 1920 1048" ]
}

@test "LAYOUT_MONITOR picks a named output" {
  LAYOUT_MONITOR=eDP-1-1 run wa get_target_work_area "$XR_LAPTOP" "$WM_LAPTOP"
  [ "$output" = "0 32 2560 1568" ]
}

@test "LAYOUT_MONITOR naming a missing output falls back to the primary" {
  LAYOUT_MONITOR=DP-9 run wa get_target_monitor "$XR_LAPTOP" "$WM_LAPTOP"
  [ "$output" = "HDMI-0 1920x1080+2560+0" ]
}

@test "no primary flag falls back to the first connected output" {
  local xr='eDP-1 connected 2560x1600+0+0 (normal) 345mm x 215mm\nHDMI-1 connected 1920x1080+2560+0 (normal) 476mm x 267mm'
  run wa get_target_monitor "$xr" "$WM_LAPTOP"
  [ "$output" = "eDP-1 2560x1600+0+0" ]
}

@test "no xrandr output falls back to the raw work area" {
  run wa get_target_work_area "" "$WM_4K"
  [ "$output" = "0 64 3840 2096" ]
}

@test "no wmctrl output falls back to the raw monitor" {
  run wa get_target_work_area "$XR_LAPTOP" ""
  [ "$output" = "2560 0 1920 1080" ]
}

@test "nothing available fails" {
  run wa get_target_work_area "" ""
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "panel is compact below 2560px on the main screen and full on a 4k screen" {
  run wa panel_compact "$XR_LAPTOP" "$WM_LAPTOP"
  [ "$status" -eq 0 ]
  run wa panel_compact "$XR_4K" "$WM_4K"
  [ "$status" -eq 1 ]
  PANEL_COMPACT_BELOW=1920 run wa panel_compact "$XR_LAPTOP" "$WM_LAPTOP"
  [ "$status" -eq 1 ]
}

@test "panel label size drops two points when compact" {
  run wa "panel_label_size 12" "$XR_LAPTOP" "$WM_LAPTOP"
  [ "$output" = "10" ]
  run wa "panel_label_size 12" "$XR_4K" "$WM_4K"
  [ "$output" = "12" ]
}

@test "panel button padding tightens on a narrow main screen and stays default on 4k" {
  local adapt="${BATS_TEST_DIRNAME}/../../scripts/__panel_adapt.sh"
  run wa "$adapt --print" "$XR_LAPTOP" "$WM_LAPTOP"
  [ "$output" = "4" ]
  run wa "$adapt --print" "$XR_4K" "$WM_4K"
  [ "$output" = "0" ]
}

@test "screen lookups never re-probe the outputs" {
  # A bare xrandr or --query re-reads every output's EDID inside the X server
  # (100-190ms here) and one-second argos applets calling the lib stalled the
  # desktop and typing with it. --current returns the cached configuration.
  run bash -c "grep -hE '(^|[^/])xrandr ' '$LIB' '${BATS_TEST_DIRNAME}/../../scripts/__window_size_cycle.sh' | grep -vE '^[[:space:]]*#' | grep -v -- '--current'"
  [ -z "$output" ]
  run grep -c 'xrandr --current' "$LIB"
  [ "$output" -ge 3 ]
}
