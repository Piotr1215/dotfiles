#!/usr/bin/env bats

# xdotool search returns windows in stacking order, so a `head -n 1` pick means
# "bottom-most terminal in the stack". With several Alacritty windows open, each
# holding its own tmux session, raising any one of them reshuffled that list and
# the next layout tiled a different terminal, which reads as the split swapping
# tmux sessions at random. These tests pin the two properties that stop it: the
# focused terminal wins, and the fallback does not move when stacking does.

setup() {
  LAYOUTS="${BATS_TEST_DIRNAME}/../../scripts/__layouts.sh"
}

# Load the real helper out of __layouts.sh (the script itself exits without a
# layout argument) with xdotool stubbed to a scripted stacking order.
pick() {
  local stack="$1" active="$2"
  STACK="$stack" ACTIVE="$active" bash -c '
    IFS=$'"'"'\n\t'"'"'
    source <(sed -n "/^get_alacritty_window()/,/^}/p" "'"$LAYOUTS"'")
    xdotool() {
      case "$1 $2" in
        "search --onlyvisible") [[ -n "$STACK" ]] && tr " " "\n" <<< "$STACK" ;;
        "getactivewindow ") [[ -n "$ACTIVE" ]] && printf "%s\n" "$ACTIVE" ;;
      esac
      return 0
    }
    get_alacritty_window
  '
}

@test "focused terminal is picked regardless of stacking order" {
  run pick "125829125 96468997 102760453 62914565" 102760453
  [ "$status" -eq 0 ]
  [ "$output" = "102760453" ]

  run pick "62914565 102760453 125829125 96468997" 102760453
  [ "$status" -eq 0 ]
  [ "$output" = "102760453" ]
}

@test "focus outside alacritty falls back to the same window every time" {
  # 73400324 is a browser or the rofi picker: neither is in the terminal list.
  run pick "125829125 96468997 102760453 62914565" 73400324
  [ "$output" = "62914565" ]

  run pick "62914565 102760453 125829125 96468997" 73400324
  [ "$output" = "62914565" ]
}

@test "handoff pins its source terminal after the browser takes focus" {
  export LAYOUT_ALACRITTY_WINDOW=96468997
  run pick "125829125 96468997 102760453 62914565" 73400324
  [ "$status" -eq 0 ]
  [ "$output" = "96468997" ]
}

@test "stale handoff terminal falls back to a real terminal" {
  export LAYOUT_ALACRITTY_WINDOW=999
  run pick "96468997 62914565" 73400324
  [ "$output" = "62914565" ]
}

@test "handoff browser window bypasses normal layout cycling" {
  run bash -c '
    source <(sed -n "/^alacritty_firefox_vertical()/,/^}/p" "$1")
    get_browser_windows() { printf "111\n222\n"; }
    cycle_browser_window() { echo unexpected-cycle >&2; return 1; }
    tile_left() { echo "left:$1"; }
    tile_right() { echo "right:$1"; }
    LAYOUT_BROWSER_WINDOW=222 alacritty_firefox_vertical 333
  ' bash "$LAYOUTS"
  [ "$status" -eq 0 ]
  [ "$output" = $'left:222\nright:333' ]
}

# Same harness for next_alacritty_window, with xprop stubbed to a scripted
# _NET_CLIENT_LIST_STACKING (bottom to top, hex, as xprop prints it).
pick_next() {
  local stack="$1" active="$2" stacking="$3"
  STACK="$stack" ACTIVE="$active" STACKING="$stacking" bash -c '
    IFS=$'"'"'\n\t'"'"'
    source <(sed -n "/^next_alacritty_window()/,/^}/p" "'"$LAYOUTS"'")
    xdotool() {
      case "$1 $2" in
        "search --onlyvisible") [[ -n "$STACK" ]] && tr " " "\n" <<< "$STACK" ;;
        "getactivewindow ") [[ -n "$ACTIVE" ]] && printf "%s\n" "$ACTIVE" ;;
      esac
      return 0
    }
    xprop() {
      [[ -n "$STACKING" ]] && printf "_NET_CLIENT_LIST_STACKING(WINDOW): window id # %s\n" "$STACKING"
      return 0
    }
    next_alacritty_window
  '
}

@test "max alacritty from a terminal moves to the next terminal by xid" {
  run pick_next "96468997 62914565" 62914565 ""
  [ "$status" -eq 0 ]
  [ "$output" = "96468997" ]
}

@test "max alacritty wraps from the newest terminal to the oldest" {
  run pick_next "96468997 62914565" 96468997 ""
  [ "$output" = "62914565" ]
}

@test "max alacritty with one terminal keeps it" {
  run pick_next "62914565" 62914565 ""
  [ "$output" = "62914565" ]
}

@test "max alacritty from another window brings back the terminal raised last" {
  # 0x3c00017 is a browser; 0x5c00005 (96468997) sits above 0x3c00005 (62914565).
  run pick_next "62914565 96468997" 62914583 "0x3c00005, 0x3c00017, 0x5c00005"
  [ "$output" = "96468997" ]

  run pick_next "62914565 96468997" 62914583 "0x5c00005, 0x3c00017, 0x3c00005"
  [ "$output" = "62914565" ]
}

@test "max alacritty without a stacking list falls back to the lowest xid" {
  run pick_next "96468997 62914565" 73400324 ""
  [ "$output" = "62914565" ]
}

@test "max alacritty with no terminal fails" {
  run pick_next "" 73400324 ""
  [ "$status" -eq 1 ]
}

@test "max alacritty cycles instead of reusing the split-layout pick" {
  run sed -n '/^max_alacritty()/,/^}/p' "$LAYOUTS"
  [[ "$output" == *'next_alacritty_window'* ]]
}

@test "no active window falls back to the lowest xid" {
  run pick "96468997 62914565" ""
  [ "$output" = "62914565" ]
}

@test "no alacritty window returns empty and fails" {
  run pick "" 73400324
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "every alacritty pick goes through the helper" {
  run grep -c 'classname Alacritty' "$LAYOUTS"
  # Three direct searches survive by design: the two helpers (focused pick for
  # splits, cycling pick for max), and the two-window split (layout 17) which
  # needs the sorted pair, not a single window.
  [ "$output" -eq 3 ]
}

# The work area no longer starts at 0,0 when a laptop panel sits left of the
# main screen, so a width used as an x coordinate lands on the wrong screen.
@test "no tile call uses a bare width as its x coordinate" {
  run grep -nE 'tile_place [^ ]+ "\$(HALF_W|half_w|third_w|two_third_w)"' "$LAYOUTS"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "work area comes from the screen lib, not the raw wmctrl bounding box" {
  run grep -c 'wmctrl -d' "$LAYOUTS"
  [ "$output" -eq 0 ]
  run grep -c 'get_target_work_area' "$LAYOUTS"
  [ "$output" -eq 1 ]
}
