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
  # Two direct searches survive by design: the helper itself, and the two-window
  # split (layout 17) which needs the sorted pair, not a single window.
  [ "$output" -eq 2 ]
}
