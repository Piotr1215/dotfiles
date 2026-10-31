#!/usr/bin/env bats

# The voice bridge rows and line status blink of the Argos mic item. systemctl and
# the toggle board are stubs, so no test touches the real service, flag or board.
# Blink failures to guard: a marker that keeps blinking after its window, a
# single button line (argos cycles only two or more), a blink that leaks into the
# menu, and the relay drifting onto another marker path, which would leave a
# published line looking lost.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../.config/argos/notion-mic.1s.sh"
  STUBS="${BATS_TEST_TMPDIR}/bin"
  CALLS="${BATS_TEST_TMPDIR}/calls"
  mkdir -p "$STUBS"
  export KLOD_VOICE_STATE="${BATS_TEST_TMPDIR}/klod-voice"
  mkdir -p "$KLOD_VOICE_STATE"
  export XDG_RUNTIME_DIR="${BATS_TEST_TMPDIR}/run"
  mkdir -p "$XDG_RUNTIME_DIR"
  MARKER="${XDG_RUNTIME_DIR}/voice-mode-line"
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
  [[ "$output" == *$'\n'"<b>Voice bridge</b> | font=monospace"* ]]
  [[ "$output" == *$'\n'"⚪ Hands-free listening: off, click to turn on | bash='\"${TOGGLES_BIN}\" __run voice-mode on'"* ]]
  [[ "$output" == *$'\n'"⚪ Spoken replies (Piper): off, click to turn on | bash='\"${TOGGLES_BIN}\" __run voice-replies on'"* ]]
  [[ "$output" != *"#44aaff"* ]]
  [[ "$output" != *"All off"* ]]
}

@test "listening shows a blue dot on the panel line and a working stop row" {
  voice_mode_is 0
  touch "${KLOD_VOICE_STATE}/off"
  run bash "$SCRIPT"
  [[ "${lines[0]}" == *"#44aaff"* ]]
  [[ "$output" == *$'\n'"🟢 Hands-free listening: on, click to turn off | bash='\"${TOGGLES_BIN}\" __run voice-mode off'"* ]]
  [[ "$output" == *$'\n'"⚪ Spoken replies (Piper): off"* ]]
  [[ "$output" == *$'\n'"🛑 All off (normal mode) | bash='\"${SCRIPT}\" --voice-off'"* ]]
}

@test "spoken replies alone still offer the way back to normal" {
  voice_mode_is 3
  run bash "$SCRIPT"
  [[ "$output" == *$'\n'"🟢 Spoken replies (Piper): on, click to turn off | bash='\"${TOGGLES_BIN}\" __run voice-replies off'"* ]]
  [[ "$output" == *$'\n'"🛑 All off (normal mode)"* ]]
}

@test "all off switches both toggles off through the board" {
  voice_mode_is 0
  run bash "$SCRIPT" --voice-off
  [ "$status" -eq 0 ]
  [ "$(cat "$CALLS")" = "$(printf '__run voice-mode off\n__run voice-replies off')" ]
}

# blinks <status> <colour>: the dot takes the colour on one line and goes dark on the other.
blinks() {
  voice_mode_is 0
  printf '%s' "$1" >"$MARKER"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "${lines[2]}" = "---" ]
  [[ "${lines[0]}" == *" <span color='$2'>●</span> | font='monospace' size="*" dropdown=false" ]]
  [[ "${lines[1]}" == *" <span color='#222222'>●</span> | font='monospace' size="*" dropdown=false" ]]
  [[ "${lines[0]}" != *"#44aaff"* ]]
}

@test "with no spoken line the mic stays one line with the blue dot" {
  voice_mode_is 0
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "---" ]
  [[ "${lines[0]}" == *"#44aaff"* ]]
  [[ "${lines[0]}" != *"dropdown=false"* ]]
}

@test "a line the bus took blinks green" {
  blinks sent '#44ff44'
}

@test "a line that named no agent blinks orange" {
  blinks dropped '#ffaa00'
}

@test "a line that could not be sent blinks red" {
  blinks failed '#ff4444'
}

@test "a marker caught half written does not blink" {
  voice_mode_is 0
  : >"$MARKER"
  run bash "$SCRIPT"
  [ "${lines[1]}" = "---" ]
}

@test "a blink keeps the panel size, so the bar does not shift" {
  voice_mode_is 0
  size_of() { sed -n '1s/.* size=\([0-9.]*\).*/\1/p'; }
  idle="$(bash "$SCRIPT" | size_of)"
  printf sent >"$MARKER"
  [ -n "$idle" ]
  [ "$(bash "$SCRIPT" | size_of)" = "$idle" ]
}

@test "a blink leaves the menu alone" {
  voice_mode_is 0
  menu() { sed -n '/^---$/,$p'; }
  idle="$(bash "$SCRIPT" | menu)"
  printf sent >"$MARKER"
  [ "$(bash "$SCRIPT" | menu)" = "$idle" ]
}

@test "the blink still runs inside its window" {
  voice_mode_is 0
  printf sent >"$MARKER"
  touch -d '-3 seconds' "$MARKER"
  run bash "$SCRIPT"
  [ "${lines[2]}" = "---" ]
}

@test "the blink stops once its window has passed" {
  voice_mode_is 0
  printf sent >"$MARKER"
  touch -d '-5 seconds' "$MARKER"
  run bash "$SCRIPT"
  [ "${lines[1]}" = "---" ]
  [[ "${lines[0]}" == *"#44aaff"* ]]
}

@test "the relay writes the marker the applet reads" {
  grep -q "'voice-mode-line'" "${BATS_TEST_DIRNAME}/../../scripts/__voice_mode.py"
  grep -q '/voice-mode-line"' "$SCRIPT"
}
