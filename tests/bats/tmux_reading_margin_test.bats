#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__tmux_toggle_reading_margin.sh"
  SOCKET_NAME="reading-margin-${BATS_TEST_NUMBER}-$$"
  MODE_FILE="${BATS_TEST_TMPDIR}/timeoff-mode"
  COMMAND_LOG="${BATS_TEST_TMPDIR}/margin-command"
  tmux -L "$SOCKET_NAME" -f /dev/null new-session -d -s test -x 120 -y 30
  PANE_ID="$(tmux -L "$SOCKET_NAME" display-message -p '#{pane_id}')"
  tmux -L "$SOCKET_NAME" set-environment -g TMUX_READING_MARGIN_TIMEOFF_FILE "$MODE_FILE"
  tmux -L "$SOCKET_NAME" set-environment -g TMUX_READING_MARGIN_WORK_COMMAND \
    "printf 'work\\n' > '$COMMAND_LOG'; exec sleep infinity"
  tmux -L "$SOCKET_NAME" set-environment -g TMUX_READING_MARGIN_WEEKEND_COMMAND \
    "printf 'weekend\\n' > '$COMMAND_LOG'; exec sleep infinity"
}

teardown() {
  tmux -L "$SOCKET_NAME" kill-server 2>/dev/null || true
}

toggle_margin() {
  tmux -L "$SOCKET_NAME" run-shell "$SCRIPT '$PANE_ID'"
}

wait_for_command() {
  for _ in {1..20}; do
    [ -s "$COMMAND_LOG" ] && return
    sleep 0.05
  done
  return 1
}

@test "reading margin toggles a left third without taking focus" {
  toggle_margin

  margin_id="$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_pane)"
  [ "$(tmux -L "$SOCKET_NAME" list-panes -F '#{pane_id}' | wc -l)" -eq 2 ]
  [ "$(tmux -L "$SOCKET_NAME" display-message -p -t "$margin_id" '#{pane_left}')" -eq 0 ]
  margin_width="$(tmux -L "$SOCKET_NAME" display-message -p -t "$margin_id" '#{pane_width}')"
  [ "$margin_width" -ge 38 ]
  [ "$margin_width" -le 40 ]
  [ "$(tmux -L "$SOCKET_NAME" display-message -p '#{pane_id}')" = "$PANE_ID" ]
  messages="$(tmux -L "$SOCKET_NAME" show-messages)"
  [[ "$messages" != *"Reading margin"* ]]

  toggle_margin

  [ "$(tmux -L "$SOCKET_NAME" list-panes -F '#{pane_id}' | wc -l)" -eq 1 ]
  [ -z "$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_pane)" ]
  [ "$(tmux -L "$SOCKET_NAME" display-message -p '#{pane_id}')" = "$PANE_ID" ]
  messages="$(tmux -L "$SOCKET_NAME" show-messages)"
  [[ "$messages" != *"Reading margin"* ]]
}

@test "reading margin spans the window beside an existing split" {
  tmux -L "$SOCKET_NAME" split-window -v -t "$PANE_ID"
  split_pane_id="$(tmux -L "$SOCKET_NAME" display-message -p '#{pane_id}')"

  tmux -L "$SOCKET_NAME" run-shell "$SCRIPT '$split_pane_id'"

  margin_id="$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_pane)"
  [ "$(tmux -L "$SOCKET_NAME" display-message -p -t "$margin_id" '#{pane_top}')" -eq 0 ]
  margin_height="$(tmux -L "$SOCKET_NAME" display-message -p -t "$margin_id" '#{pane_height}')"
  [ "$margin_height" -eq "$(tmux -L "$SOCKET_NAME" display-message -p '#{window_height}')" ]
  [ "$(tmux -L "$SOCKET_NAME" display-message -p '#{pane_id}')" = "$split_pane_id" ]
}

@test "reading margin recovers after its pane is closed elsewhere" {
  toggle_margin
  old_margin="$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_pane)"
  tmux -L "$SOCKET_NAME" kill-pane -t "$old_margin"

  toggle_margin

  new_margin="$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_pane)"
  [ -n "$new_margin" ]
  [ "$new_margin" != "$old_margin" ]
  [ "$(tmux -L "$SOCKET_NAME" list-panes -F '#{pane_id}' | wc -l)" -eq 2 ]
}

@test "reading margin shows cockpit at work and playlist during time off" {
  toggle_margin
  wait_for_command
  [ "$(<"$COMMAND_LOG")" = work ]
  margin_id="$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_pane)"
  [ "$(tmux -L "$SOCKET_NAME" display-message -p -t "$margin_id" '#{pane_input_off}')" -eq 1 ]
  toggle_margin

  rm -f "$COMMAND_LOG"
  touch "$MODE_FILE"
  toggle_margin
  wait_for_command
  [ "$(<"$COMMAND_LOG")" = weekend ]
  margin_id="$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_pane)"
  [ "$(tmux -L "$SOCKET_NAME" display-message -p -t "$margin_id" '#{pane_input_off}')" -eq 0 ]
}

@test "ensure mode adds one unfocused margin and skips playback sessions" {
  tmux -L "$SOCKET_NAME" run-shell "$SCRIPT --ensure-session test"
  first_margin="$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_pane)"
  [ -n "$first_margin" ]
  [ "$(tmux -L "$SOCKET_NAME" display-message -p '#{pane_id}')" = "$PANE_ID" ]

  tmux -L "$SOCKET_NAME" run-shell "$SCRIPT --ensure-session test"
  [ "$(tmux -L "$SOCKET_NAME" show-options -wqv @reading_margin_pane)" = "$first_margin" ]

  tmux -L "$SOCKET_NAME" new-session -d -s ambient_track_1a2b
  tmux -L "$SOCKET_NAME" run-shell "$SCRIPT --ensure-session ambient_track_1a2b"
  [ "$(tmux -L "$SOCKET_NAME" list-panes -t ambient_track_1a2b -F '#{pane_id}' | wc -l)" -eq 1 ]
}
