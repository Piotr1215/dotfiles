#!/usr/bin/env bats

# Geometry below is what tmux 3.8 reports for a 60x20 float in a 200x50
# window at each move-pane -P position (left, top, width, height).

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  script="$repo_root/scripts/__tmux_float_step.sh"
  # shellcheck source=/dev/null
  source "$script"
}

at() { # position -> "left top width height"
  case "$1" in
    top-left) echo "1 1 58 18" ;;
    top-centre) echo "71 1 58 18" ;;
    top-right) echo "141 1 58 18" ;;
    centre) echo "71 16 58 18" ;;
    bottom-left) echo "1 31 58 18" ;;
    bottom-right) echo "141 31 58 18" ;;
  esac
}

step() { # from direction -> target
  # shellcheck disable=SC2046
  float_target "$2" $(at "$1") 200 50
}

@test "arrows go round the four corners and keep the other axis" {
  [ "$(step top-left right)" = top-right ]
  [ "$(step top-right down)" = bottom-right ]
  [ "$(step bottom-right left)" = bottom-left ]
  [ "$(step bottom-left up)" = top-left ]
}

@test "an arrow toward the side a float is already on leaves it in that corner" {
  [ "$(step top-left left)" = top-left ]
  [ "$(step top-left up)" = top-left ]
  [ "$(step bottom-right right)" = bottom-right ]
  [ "$(step bottom-right down)" = bottom-right ]
}

@test "arrows never stop at an edge centre" {
  for from in top-left top-centre top-right centre bottom-left bottom-right; do
    for dir in left right up down; do
      case "$(step "$from" "$dir")" in
        top-left | top-right | bottom-left | bottom-right) ;;
        *) return 1 ;;
      esac
    done
  done
}

@test "from the centre an arrow goes to the top-left side of the tie" {
  [ "$(step centre left)" = top-left ]
  [ "$(step centre right)" = top-right ]
  [ "$(step centre down)" = bottom-left ]
}

@test "a float touching no edge goes by its centre" {
  # centre (150, 40) of 200x50 is right and bottom
  [ "$(float_target up 120 30 60 20 200 50)" = top-right ]
  [ "$(float_target left 120 30 60 20 200 50)" = bottom-left ]
}

@test "an unknown direction fails" {
  run float_target sideways 1 1 58 18 200 50
  [ "$status" -ne 0 ]
}

@test "on a real tmux server the script moves a float and leaves a tiled pane" {
  command -v tmux >/dev/null || skip "tmux not installed"
  local sock="float-step-$$"
  tmux -L "$sock" -f /dev/null new-session -d -s t -x 200 -y 50
  tmux -L "$sock" new-pane -t t -x 60 -y 20 -X 70 -Y 15 || {
    tmux -L "$sock" kill-server
    skip "tmux has no floating panes"
  }
  local float tiled path
  float=$(tmux -L "$sock" display -p -t t '#{pane_id}')
  tiled=$(tmux -L "$sock" list-panes -t t -F '#{pane_floating_flag} #{pane_id}' | awk '$1==0{print $2; exit}')
  path=$(tmux -L "$sock" display -p '#{socket_path}')
  tmux -L "$sock" move-pane -t "$float" -P top-left

  TMUX="$path,0,0" "$script" right "$float"
  geo=$(tmux -L "$sock" display -p -t "$float" '#{pane_left} #{pane_top}')
  TMUX="$path,0,0" "$script" down "$float"
  geo2=$(tmux -L "$sock" display -p -t "$float" '#{pane_left} #{pane_top}')
  before=$(tmux -L "$sock" display -p -t "$tiled" '#{pane_left} #{pane_top} #{pane_width}')
  TMUX="$path,0,0" run "$script" right "$tiled"
  after=$(tmux -L "$sock" display -p -t "$tiled" '#{pane_left} #{pane_top} #{pane_width}')
  tmux -L "$sock" kill-server

  [ "$geo" = "141 1" ]
  [ "$geo2" = "141 31" ]
  [ "$status" -eq 0 ]
  [ "$before" = "$after" ]
}
