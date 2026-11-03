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
@test "ctrl-e runs a toggle's own edit action and falls back to the config" {
  cat >>"$TOGGLES_CONF" <<EOF
toggle_edit_action "alpha" "touch ${FLAGS}/alpha_edited"
EOF

  run "$SCRIPT" __edit '[off] alpha'
  [ "$status" -eq 0 ]
  [ -f "${FLAGS}/alpha_edited" ]

  fake_editor="${BATS_TEST_TMPDIR}/fake-editor"
  cat >"$fake_editor" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$1" > "${BATS_TEST_TMPDIR}/edit.log"
EOF
  chmod +x "$fake_editor"

  run env EDITOR="$fake_editor" "$SCRIPT" __edit '[off] beta'
  [ "$status" -eq 0 ]
  [[ "$(<"${BATS_TEST_TMPDIR}/edit.log")" == "$TOGGLES_CONF" ]]
}

@test "an info action prints live output in the preview and only there" {
  cat >>"$TOGGLES_CONF" <<EOF
toggle_info_action "alpha" "echo scored-42-rows"
EOF

  run "$SCRIPT" __preview "[off] alpha"
  [ "$status" -eq 0 ]
  [[ "$output" == *"info:"* ]]
  [[ "$output" == *"scored-42-rows"* ]]

  run "$SCRIPT" __preview "[off] beta"
  [ "$status" -eq 0 ]
  [[ "$output" != *"info:"* ]]
}

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
    toggle_edit_action() { :; }
    toggle_info_action() { :; }
    source "$1"
    echo "registered ${#seen[@]}"
  ' _ "${BATS_TEST_DIRNAME}/../../scripts/__toggles.conf"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^registered\ [0-9]+$ ]]
  [ "${output#registered }" -ge 1 ]
}

@test "voice-mode off persists in a flag the unit reads at login, and never disables" {
  stub="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$stub"
  printf '#!/bin/sh\necho "$*" >>"%s/calls"\n' "$BATS_TEST_TMPDIR" >"$stub/systemctl"
  chmod +x "$stub/systemctl"
  export HOME="${BATS_TEST_TMPDIR}/home" TOGGLES_CONF="${BATS_TEST_DIRNAME}/../../scripts/__toggles.conf"
  flag="$HOME/.local/state/klod-voice/no-listening"
  PATH="$stub:$PATH" run "$SCRIPT" __run voice-mode off
  [ -e "$flag" ]
  PATH="$stub:$PATH" run "$SCRIPT" __run voice-mode on
  [ ! -e "$flag" ]
  grep -Fx -- '--user stop voice-mode.service' "$BATS_TEST_TMPDIR/calls"
  grep -Fx -- '--user enable --now voice-mode.service' "$BATS_TEST_TMPDIR/calls"
  # disable also deletes the unit's link, so the next start finds no unit.
  ! grep -q disable "$BATS_TEST_TMPDIR/calls"
  grep -Fx 'ConditionPathExists=!%h/.local/state/klod-voice/no-listening' \
    "${BATS_TEST_DIRNAME}/../../.config/systemd/user/voice-mode.service"
}

setup_classif_toggle() {
  export HOME="${BATS_TEST_TMPDIR}/classif-home"
  export PATH="${BATS_TEST_TMPDIR}/classif-bin:$PATH"
  export CLASSIF_TOGGLE_SYSTEMCTL_LOG="${BATS_TEST_TMPDIR}/systemctl.log"
  export CLASSIF_TOGGLE_CURL_LOG="${BATS_TEST_TMPDIR}/curl.log"
  mkdir -p "$HOME/.claude/config" "$HOME/.config/classif" \
    "$HOME/dev/dotfiles/.config/classif" "$HOME/.local/state/classif-vm" \
    "$BATS_TEST_TMPDIR/classif-bin"
  cat >"$HOME/.claude/config/quick-decisions.json" <<'EOF'
{
  "provider": "classif",
  "classif_hosts": "localhost:11434=winnow:12b-q4_K_M",
  "openai_project": null
}
EOF
  printf 'localhost:11434=winnow:12b-q4_K_M\n' >"$HOME/dev/dotfiles/.config/classif/hosts"
  ln -s "$HOME/dev/dotfiles/.config/classif/hosts" "$HOME/.config/classif/hosts"
  touch "$HOME/.local/state/classif-vm/pc-mode"
  cat >"$BATS_TEST_TMPDIR/classif-bin/systemctl" <<'EOF'
#!/bin/sh
echo "$*" >>"$CLASSIF_TOGGLE_SYSTEMCTL_LOG"
EOF
  cat >"$BATS_TEST_TMPDIR/classif-bin/curl" <<'EOF'
#!/bin/sh
echo "$*" >>"$CLASSIF_TOGGLE_CURL_LOG"
case "$*" in
  */api/ps*)
    [ "${OLLAMA_UP:-1}" = 1 ] || exit 7
    if [ "${OLLAMA_LOADED:-1}" = 1 ]; then
      printf '{"models":[{"name":"winnow:12b-q4_K_M"}]}\n'
    else
      printf '{"models":[]}\n'
    fi
    ;;
  */api/generate*) [ "${UNLOAD_FAIL:-0}" = 0 ] ;;
  *) exit 2 ;;
esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/classif-bin/systemctl" "$BATS_TEST_TMPDIR/classif-bin/curl"
  HELPER="${BATS_TEST_DIRNAME}/../../scripts/__classif_vm_toggle.py"
}

@test "classif VM toggle updates both routing files and unloads local Ollama" {
  setup_classif_toggle
  run python3 "$HELPER" status
  [ "$status" -eq 1 ]

  run python3 "$HELPER" vm
  [ "$status" -eq 0 ]
  run python3 "$HELPER" status
  [ "$status" -eq 0 ]
  grep -F '"classif_hosts": "127.0.0.1:11435=winnow:12b-q4_K_M"' \
    "$HOME/.claude/config/quick-decisions.json"
  [ -L "$HOME/.config/classif/hosts" ]
  grep -Fx '127.0.0.1:11435=winnow:12b-q4_K_M' "$HOME/.config/classif/hosts"
  grep -F 'keep_alive":0' "$CLASSIF_TOGGLE_CURL_LOG"
  grep -Fx -- '--user enable --now classif-vm-tunnel.service' "$CLASSIF_TOGGLE_SYSTEMCTL_LOG"

  run python3 "$HELPER" pc
  [ "$status" -eq 0 ]
  run python3 "$HELPER" status
  [ "$status" -eq 1 ]
  grep -Fx 'localhost:11434=winnow:12b-q4_K_M' "$HOME/.config/classif/hosts"
  grep -Fx -- '--user stop classif-vm-tunnel.service' "$CLASSIF_TOGGLE_SYSTEMCTL_LOG"
}

@test "classif VM route remains exclusive when local Ollama is unavailable" {
  setup_classif_toggle
  export OLLAMA_UP=0
  run python3 "$HELPER" vm
  [ "$status" -eq 0 ]
  run python3 "$HELPER" status
  [ "$status" -eq 0 ]
  ! grep -q '/api/generate' "$CLASSIF_TOGGLE_CURL_LOG"
}

@test "classif VM mode does not load Winnow just to unload it" {
  setup_classif_toggle
  export OLLAMA_LOADED=0
  run python3 "$HELPER" vm
  [ "$status" -eq 0 ]
  ! grep -q '/api/generate' "$CLASSIF_TOGGLE_CURL_LOG"
}

@test "classif unload errors are reported without restoring laptop routing" {
  setup_classif_toggle
  export UNLOAD_FAIL=1
  run python3 "$HELPER" vm
  [ "$status" -eq 1 ]
  [[ "$output" == *"classif vm switch failed"* ]]
  run python3 "$HELPER" status
  [ "$status" -eq 0 ]
}

@test "classif toggle refuses mismatched configuration without acting" {
  setup_classif_toggle
  printf '127.0.0.1:11435=winnow:12b-q4_K_M\n' >"$HOME/.config/classif/hosts"
  run python3 "$HELPER" status
  [ "$status" -eq 2 ]
  [[ "$output" == *"disagree"* ]]
  [ ! -e "$CLASSIF_TOGGLE_SYSTEMCTL_LOG" ]
  [ ! -e "$CLASSIF_TOGGLE_CURL_LOG" ]
}

@test "game action spec inherits the host selected by the toggle" {
  run python3 -c 'import json,sys; assert "hosts" not in json.load(open(sys.argv[1]))' \
    "${BATS_TEST_DIRNAME}/../../.config/classif/specs/game-action.json"
  [ "$status" -eq 0 ]
}

@test "checked-in classif hosts default to only the forwarded VM endpoint" {
  hosts="${BATS_TEST_DIRNAME}/../../.config/classif/hosts"
  run bash -c 'grep -vE "^[[:space:]]*(#|$)" "$1"' _ "$hosts"
  [ "$status" -eq 0 ]
  [ "$output" = "127.0.0.1:11435=winnow:12b-q4_K_M" ]
}
