#!/usr/bin/env bats

# The remaining voice bridge rows, actions, and isolation from hands-free state.
# The service and toggle board are stubs, so tests do not touch the real service or board.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../.config/argos/notion-mic.1s.sh"
  STUBS="${BATS_TEST_TMPDIR}/bin"
  CALLS="${BATS_TEST_TMPDIR}/calls"
  mkdir -p "$STUBS"
  printf '#!/usr/bin/env bash\nexit 1\n' >"${STUBS}/pactl"
  chmod +x "${STUBS}/pactl"
  export KLOD_VOICE_STATE="${BATS_TEST_TMPDIR}/klod-voice"
  mkdir -p "$KLOD_VOICE_STATE"
  export XDG_RUNTIME_DIR="${BATS_TEST_TMPDIR}/run"
  mkdir -p "$XDG_RUNTIME_DIR"
  export TOGGLES_BIN="${STUBS}/toggles"
  printf '#!/usr/bin/env bash\necho "$*" >>"%s"\n' "$CALLS" >"$TOGGLES_BIN"
  chmod +x "$TOGGLES_BIN"
  export PATH="${STUBS}:${PATH}"
}

voice_mode_is() {
  printf '#!/usr/bin/env bash\nexit %s\n' "$1" >"${STUBS}/systemctl"
  chmod +x "${STUBS}/systemctl"
}

@test "with spoken replies off the menu offers to turn them on" {
  voice_mode_is 3
  touch "${KLOD_VOICE_STATE}/off"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\n'"<b>Voice bridge</b> | font=monospace"* ]]
  [[ "$output" == *$'\n'"⚪ Spoken replies (Piper): off, click to turn on | bash='\"${TOGGLES_BIN}\" __run voice-replies on'"* ]]
  [[ "$output" != *"#44aaff"* ]]
  [[ "$output" != *"All off"* ]]
}

@test "spoken replies alone still offer the way back to normal" {
  voice_mode_is 3
  run bash "$SCRIPT"
  [[ "$output" == *$'\n'"🟢 Spoken replies (Piper): on, click to turn off | bash='\"${TOGGLES_BIN}\" __run voice-replies off'"* ]]
  [[ "$output" == *$'\n'"🛑 All off (normal mode)"* ]]
}

@test "the whole replies row follows its flag and switches through the board" {
  voice_mode_is 3
  run bash "$SCRIPT"
  [[ "$output" == *$'\n'"⚪ Read whole replies: off, click to turn on | bash='\"${TOGGLES_BIN}\" __run voice-replies-whole on'"* ]]
  touch "${KLOD_VOICE_STATE}/whole"
  run bash "$SCRIPT"
  [[ "$output" == *$'\n'"🟢 Read whole replies: on, click to turn off | bash='\"${TOGGLES_BIN}\" __run voice-replies-whole off'"* ]]
}

@test "a click on tempo steps normal, fast, slow and back" {
  voice_mode_is 3
  tempo="${KLOD_VOICE_STATE}/tempo"
  run bash "$SCRIPT"
  [[ "$output" == *$'\n'"⏱ Speech tempo: normal, click to change | bash='\"${SCRIPT}\" --tempo'"* ]]
  bash "$SCRIPT" --tempo
  [ "$(cat "$tempo")" = "0.8" ]
  run bash "$SCRIPT"
  [[ "$output" == *"Speech tempo: fast,"* ]]
  bash "$SCRIPT" --tempo
  [ "$(cat "$tempo")" = "1.2" ]
  run bash "$SCRIPT"
  [[ "$output" == *"Speech tempo: slow,"* ]]
  bash "$SCRIPT" --tempo
  [ ! -s "$tempo" ]
  run bash "$SCRIPT"
  [[ "$output" == *"Speech tempo: normal,"* ]]
}

@test "all off switches both toggles off through the board" {
  voice_mode_is 0
  run bash "$SCRIPT" --voice-off
  [ "$status" -eq 0 ]
  [ "$(cat "$CALLS")" = "$(printf '__run voice-mode off\n__run voice-replies off')" ]
}

@test "active hands-free state does not appear in the applet" {
  voice_mode_is 0
  [ ! -e "${KLOD_VOICE_STATE}/no-continue" ]
  printf sent >"${XDG_RUNTIME_DIR}/voice-mode-line"
  printf travel-prep >"${XDG_RUNTIME_DIR}/voice-mode-channel"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "---" ]
  for unwanted in "Hands-free" "Keep channel open" "Resume speech" "travel-prep" "#44aaff" "#ffee00" "dropdown=false"; do
    [[ "$output" != *"$unwanted"* ]] || return 1
  done
}

@test "all off is absent when only hands-free service is active" {
  voice_mode_is 0
  touch "${KLOD_VOICE_STATE}/off"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"All off"* ]]
}
