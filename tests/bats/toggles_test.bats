#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__toggles.sh"
  FLAGS="${BATS_TEST_TMPDIR}/flags"
  mkdir -p "$FLAGS"
  export TOGGLES_CONF="${BATS_TEST_TMPDIR}/toggles.conf"
  export TOGGLES_STATE_DIR="${BATS_TEST_TMPDIR}/state"
  write_conf
}

# Fake toggles only: flag files under the test tmpdir, never the real seeds,
# never tmux, never /tmp/timeoff_mode.
write_conf() {
  cat >"$TOGGLES_CONF" <<EOF
alpha_status() { [ -f "${FLAGS}/alpha" ]; }
alpha_on() { touch "${FLAGS}/alpha"; }
alpha_off() { rm -f "${FLAGS}/alpha"; }

beta_status() { [ -f "${FLAGS}/beta" ]; }
beta_on() { touch "${FLAGS}/beta"; }
beta_off() { rm -f "${FLAGS}/beta"; }

broken_status() { echo "sensor offline" >&2; return 2; }
broken_on() { touch "${FLAGS}/broken"; }
broken_off() { rm -f "${FLAGS}/broken"; }

chain_status() { [ -f "${FLAGS}/chain" ]; }
chain_on() {
	touch "${FLAGS}/chain_step1"
	/bin/sh -c 'echo "step2 blew up" >&2; exit 7'
	touch "${FLAGS}/chain_step3"
	touch "${FLAGS}/chain"
}
chain_off() { rm -f "${FLAGS}/chain"; }

toggle_register "alpha" "alpha_status" "alpha_on" "alpha_off"
toggle_register "beta" "beta_status" "beta_on" "beta_off" \
	"Beta guards the beta flag used by the fake suite."
toggle_register "broken" "broken_status" "broken_on" "broken_off"
toggle_register "chain" "chain_status" "chain_on" "chain_off"
EOF
}

@test "render tags every toggle with its current state" {
  touch "${FLAGS}/alpha"

  run "$SCRIPT" __render

  [ "$status" -eq 0 ]
  [[ "$output" == *"[on ] alpha"* ]]
  [[ "$output" == *"[off] beta"* ]]
}

@test "flip turns an off toggle on and an on toggle off" {
  run "$SCRIPT" __flip alpha
  [ "$status" -eq 0 ]
  [ -f "${FLAGS}/alpha" ]
  [[ "$(<"${TOGGLES_STATE_DIR}/alpha.last")" == *"alpha: off -> on"* ]]

  run "$SCRIPT" __flip alpha
  [ "$status" -eq 0 ]
  [ ! -f "${FLAGS}/alpha" ]
  [[ "$(<"${TOGGLES_STATE_DIR}/alpha.last")" == *"alpha: on -> off"* ]]
}

@test "a multi-selection flips each toggle independently" {
  touch "${FLAGS}/alpha"

  # Board rows passed through raw, tag and all, the way fzf hands over {+}
  run "$SCRIPT" __flip '[on ] alpha' '[off] beta'

  [ "$status" -eq 0 ]
  [ ! -f "${FLAGS}/alpha" ]
  [ -f "${FLAGS}/beta" ]
}

@test "a composite action stops at the first failing step" {
  run "$SCRIPT" __flip chain

  [ "$status" -eq 0 ]
  [ -f "${FLAGS}/chain_step1" ]
  [ ! -f "${FLAGS}/chain_step3" ]
  [ ! -f "${FLAGS}/chain" ]

  result="$(<"${TOGGLES_STATE_DIR}/chain.last")"
  [[ "$result" == *"outcome: failed (exit 7)"* ]]
  [[ "$result" == *"step2 blew up"* ]]
}

@test "an unreadable state renders the unknown tag and blocks the flip" {
  run "$SCRIPT" __render
  [[ "$output" == *"[?? ] broken"* ]]

  run "$SCRIPT" __flip broken

  [ "$status" -eq 0 ]
  [ ! -f "${FLAGS}/broken" ]
  result="$(<"${TOGGLES_STATE_DIR}/broken.last")"
  [[ "$result" == *"refused"* ]]
  [[ "$result" == *"sensor offline"* ]]
}

@test "preview shows the state, the pending action and the last result" {
  run "$SCRIPT" __flip alpha
  [ -f "${FLAGS}/alpha" ]

  run "$SCRIPT" __preview '[on ] alpha'

  [ "$status" -eq 0 ]
  [[ "$output" == *"toggle: alpha"* ]]
  [[ "$output" == *"state:  on"* ]]
  [[ "$output" == *"runs alpha_off to switch to off"* ]]
  [[ "$output" == *"alpha_off ()"* ]]
  [[ "$output" == *"last result:"* ]]
  [[ "$output" == *"outcome: ok (exit 0)"* ]]
}

@test "preview explains a state it cannot read instead of offering a flip" {
  run "$SCRIPT" __preview broken

  [ "$status" -eq 0 ]
  [[ "$output" == *"state:  unknown"* ]]
  [[ "$output" == *"refuses"* ]]
  [[ "$output" == *"sensor offline"* ]]
  [[ "$output" == *"(nothing run yet)"* ]]
}

@test "labels rename the two states in tags, records and preview" {
  cat >>"$TOGGLES_CONF" <<EOF
gamma_status() { [ -f "${FLAGS}/gamma" ]; }
gamma_on() { touch "${FLAGS}/gamma"; }
gamma_off() { rm -f "${FLAGS}/gamma"; }
toggle_register "gamma" "gamma_status" "gamma_on" "gamma_off" "Gamma switches between travel and home." "travel" "home"
EOF

  run "$SCRIPT" __render
  [ "$status" -eq 0 ]
  [[ "$output" == *"[home  ] gamma"* ]]
  [[ "$output" == *"[off   ] alpha"* ]]

  run "$SCRIPT" __flip gamma
  [ "$status" -eq 0 ]
  [ -f "${FLAGS}/gamma" ]
  [[ "$(<"${TOGGLES_STATE_DIR}/gamma.last")" == *"gamma: home -> travel"* ]]

  run "$SCRIPT" __preview "[travel] gamma"
  [ "$status" -eq 0 ]
  [[ "$output" == *"state:  travel"* ]]
  [[ "$output" == *"switch to home"* ]]
}

@test "preview shows the registered description paragraph" {
  run "$SCRIPT" __preview "[off] beta"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Beta guards the beta flag used by the fake suite."* ]]
}

@test "a toggle without a description still previews cleanly" {
  run "$SCRIPT" __preview "[off] alpha"

  [ "$status" -eq 0 ]
  [[ "$output" == *"state:  off"* ]]
  [[ "$output" != *"Beta guards"* ]]
}

# The suite above runs against a fake conf, so it proves nothing about the
# real one. This sources the actual file with a stubbed toggle_register: a
# syntax error, a top-level side effect that fails, or a duplicate name shows
# up here instead of at board launch. No status action ever runs.
@test "the real config parses and registers unique toggle names" {
  run bash -c '
    declare -A seen=()
    toggle_register() {
      if [ -n "${seen[$1]:-}" ]; then
        echo "duplicate toggle: $1"
        exit 1
      fi
      seen[$1]=1
    }
    source "$1"
    echo "registered ${#seen[@]}"
  ' _ "${BATS_TEST_DIRNAME}/../../scripts/__toggles.conf"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^registered\ [0-9]+$ ]]
  [ "${output#registered }" -ge 1 ]
}
