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
    centre-left) echo "1 16 58 18" ;;
    centre) echo "71 16 58 18" ;;
    centre-right) echo "141 16 58 18" ;;
    bottom-left) echo "1 31 58 18" ;;
    bottom-centre) echo "71 31 58 18" ;;
    bottom-right) echo "141 31 58 18" ;;
  esac
}

step() { # from direction -> target
  # shellcheck disable=SC2046
  float_target "$2" $(at "$1") 200 50
}

@test "arrows keep the other axis, so corners are reachable" {
  [ "$(step top-centre left)" = top-left ]
  [ "$(step top-left down)" = centre-left ]
  [ "$(step centre-left down)" = bottom-left ]
  [ "$(step bottom-left right)" = bottom-centre ]
  [ "$(step bottom-centre right)" = bottom-right ]
  [ "$(step bottom-right up)" = centre-right ]
  [ "$(step centre-right left)" = centre ]
  [ "$(step centre up)" = top-centre ]
}

@test "an arrow toward the edge a float already touches leaves it there" {
  [ "$(step top-left left)" = top-left ]
  [ "$(step top-left up)" = top-left ]
  [ "$(step bottom-right right)" = bottom-right ]
  [ "$(step bottom-right down)" = bottom-right ]
}

@test "a full-width float counts as centred on that axis" {
  [ "$(float_target right 1 1 198 18 200 50)" = top-right ]
  [ "$(float_target down 1 1 198 48 200 50)" = bottom-centre ]
}

@test "a float touching no edge is placed by its centre" {
  # centre column 100 of 200 is the middle third; row centre 30 of 50 is too
  [ "$(float_target left 70 20 60 20 200 50)" = centre-left ]
  # centre column 30 is the first third
  [ "$(float_target up 10 20 40 20 200 50)" = top-left ]
}

@test "an unknown direction fails" {
  run float_target sideways 1 1 58 18 200 50
  [ "$status" -ne 0 ]
}

@test "on a real tmux server the script steps a float and leaves a tiled pane" {
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
  tmux -L "$sock" move-pane -t "$float" -P top-centre

  TMUX="$path,0,0" "$script" left "$float"
  geo=$(tmux -L "$sock" display -p -t "$float" '#{pane_left} #{pane_top}')
  TMUX="$path,0,0" "$script" down "$float"
  geo2=$(tmux -L "$sock" display -p -t "$float" '#{pane_left} #{pane_top}')
  before=$(tmux -L "$sock" display -p -t "$tiled" '#{pane_left} #{pane_top} #{pane_width}')
  TMUX="$path,0,0" run "$script" right "$tiled"
  after=$(tmux -L "$sock" display -p -t "$tiled" '#{pane_left} #{pane_top} #{pane_width}')
  tmux -L "$sock" kill-server

  [ "$geo" = "1 1" ]
  [ "$geo2" = "1 16" ]
  [ "$status" -eq 0 ]
  [ "$before" = "$after" ]
}
