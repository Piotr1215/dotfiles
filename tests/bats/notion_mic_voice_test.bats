#!/usr/bin/env bats

# The voice bridge submenu of the Argos mic item. systemctl and the toggle board
# are stubs, so no test touches the real service, flag or board.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../.config/argos/notion-mic.5s.sh"
  STUBS="${BATS_TEST_TMPDIR}/bin"
  CALLS="${BATS_TEST_TMPDIR}/calls"
  mkdir -p "$STUBS"
  export KLOD_VOICE_STATE="${BATS_TEST_TMPDIR}/klod-voice"
  mkdir -p "$KLOD_VOICE_STATE"
  export TOGGLES_BIN="${STUBS}/toggles"
  printf '#!/usr/bin/env bash\necho "$*" >>"%s"\n' "$CALLS" >"$TOGGLES_BIN"
  chmod +x "$TOGGLES_BIN"
  export PATH="${STUBS}:${PATH}"
}

voice_mode_is() {
  printf '#!/usr/bin/env bash\nexit %s\n' "$1" >"${STUBS}/systemctl"
  chmod +x "${STUBS}/systemctl"
}

@test "with both off the menu offers to turn each on and shows no blue dot" {
  voice_mode_is 3
  touch "${KLOD_VOICE_STATE}/off"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--⚪ Hands-free listening: off, click to turn on | bash='\"${TOGGLES_BIN}\" __run voice-mode on'"* ]]
  [[ "$output" == *"--⚪ Spoken replies (Piper): off, click to turn on | bash='\"${TOGGLES_BIN}\" __run voice-replies on'"* ]]
  [[ "$output" != *"#44aaff"* ]]
  [[ "$output" != *"All off"* ]]
}

@test "listening shows a blue dot on the panel line and a working stop row" {
  voice_mode_is 0
  touch "${KLOD_VOICE_STATE}/off"
  run bash "$SCRIPT"
  [[ "${lines[0]}" == *"#44aaff"* ]]
  [[ "$output" == *"--🟢 Hands-free listening: on, click to turn off | bash='\"${TOGGLES_BIN}\" __run voice-mode off'"* ]]
  [[ "$output" == *"--⚪ Spoken replies (Piper): off"* ]]
  [[ "$output" == *"--🛑 All off (normal mode) | bash='\"${SCRIPT}\" --voice-off'"* ]]
}

@test "spoken replies alone still offer the way back to normal" {
  voice_mode_is 3
  run bash "$SCRIPT"
  [[ "$output" == *"--🟢 Spoken replies (Piper): on, click to turn off | bash='\"${TOGGLES_BIN}\" __run voice-replies off'"* ]]
  [[ "$output" == *"--🛑 All off (normal mode)"* ]]
}

@test "all off switches both toggles off through the board" {
  voice_mode_is 0
  run bash "$SCRIPT" --voice-off
  [ "$status" -eq 0 ]
  [ "$(cat "$CALLS")" = "$(printf '__run voice-mode off\n__run voice-replies off')" ]
}
