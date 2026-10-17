#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__play_track.sh"
  SOCKET_NAME="play-track-${BATS_TEST_NUMBER}-$$"
  export MUSIC_DIR="${BATS_TEST_TMPDIR}/music"
  export PLAY_TRACK_STATE_DIR="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$MUSIC_DIR" "$PLAY_TRACK_STATE_DIR" "${BATS_TEST_TMPDIR}/bin"
  touch "$MUSIC_DIR/first_song.mp3"
  # mpv stands in as a long-lived player so no audio plays
  printf '#!/usr/bin/env bash\nexec sleep infinity\n' > "${BATS_TEST_TMPDIR}/bin/mpv"
  chmod +x "${BATS_TEST_TMPDIR}/bin/mpv"
  PATH="${BATS_TEST_TMPDIR}/bin:$PATH" \
    tmux -L "$SOCKET_NAME" -f /dev/null new-session -d -s test -x 120 -y 30
  tmux -L "$SOCKET_NAME" set-option -g remain-on-exit on
}

teardown() {
  tmux -L "$SOCKET_NAME" kill-server 2>/dev/null || true
}

# Start the picker in its own pane and wait for fzf to draw the track.
start_picker() {
  PICKER_PANE="$(tmux -L "$SOCKET_NAME" new-window -d -P -F '#{pane_id}' "exec '$SCRIPT' $*")"
  wait_for_screen 'first song'
}

wait_for_screen() {
  for _ in {1..40}; do
    [[ "$(tmux -L "$SOCKET_NAME" capture-pane -p -t "$PICKER_PANE")" == *"$1"* ]] && return
    sleep 0.05
  done
  return 1
}

wait_for_playing() {
  for _ in {1..40}; do
    [ -s "$PLAY_TRACK_STATE_DIR/current_music_session.txt" ] && return
    sleep 0.05
  done
  return 1
}

@test "stay mode returns to the picker after a selection" {
  start_picker --run --stay
  tmux -L "$SOCKET_NAME" send-keys -t "$PICKER_PANE" Enter
  wait_for_playing

  wait_for_screen '► '
  [ "$(tmux -L "$SOCKET_NAME" display-message -p -t "$PICKER_PANE" '#{pane_dead}')" = 0 ]
  music_session="$(<"$PLAY_TRACK_STATE_DIR/current_music_session.txt")"
  tmux -L "$SOCKET_NAME" has-session -t "$music_session"
}

@test "run mode without stay exits after a selection" {
  start_picker --run
  tmux -L "$SOCKET_NAME" send-keys -t "$PICKER_PANE" Enter
  wait_for_playing

  for _ in {1..40}; do
    [ "$(tmux -L "$SOCKET_NAME" display-message -p -t "$PICKER_PANE" '#{pane_dead}')" = 1 ] && break
    sleep 0.05
  done
  [ "$(tmux -L "$SOCKET_NAME" display-message -p -t "$PICKER_PANE" '#{pane_dead}')" = 1 ]
}

@test "reading margin starts the picker in stay mode" {
  run grep -F '__play_track.sh\" --run --stay' "${BATS_TEST_DIRNAME}/../../scripts/__tmux_toggle_reading_margin.sh"
  [ "$status" -eq 0 ]
}
