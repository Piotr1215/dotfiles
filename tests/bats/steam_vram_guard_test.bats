#!/usr/bin/env bats

# __steam_vram_guard.sh frees the GPU for Steam: it stops the system Ollama
# service the moment a Steam client appears, and starts it again once Steam is
# gone, but only when the guard was the one that stopped it. The EVE launch
# wrapper only pauses semif, so Steam's own shader replay and any non-EVE game
# still competed with a resident llama3.2 for VRAM (2026-10-01). It also puts
# the Steam client under GameMode, which until then only EVE launches started.

setup() {
  GUARD="${BATS_TEST_DIRNAME}/../../scripts/__steam_vram_guard.sh"
  WORK="$(mktemp -d)"
  CALLS="${WORK}/calls"
  GM_CALLS="${WORK}/gamemode-calls"
  export STEAM_VRAM_GUARD_STATE="${WORK}/stopped-by-guard"

  # Stand-ins: pgrep answers from STEAM_UP with pid 4242, systemctl from
  # OLLAMA_UP, gamemoded -s from GM_REGISTERED. sudo and gamemoded -r record
  # the command instead of running it, so no test touches a real unit.
  mkdir -p "${WORK}/bin"
  cat >"${WORK}/bin/pgrep" <<'EOF'
#!/usr/bin/env bash
[ "${STEAM_UP:-0}" = 1 ] && echo 4242
EOF
  cat >"${WORK}/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
[ "$*" = "is-active --quiet ollama" ] && [ "${OLLAMA_UP:-0}" = 1 ]
EOF
  cat >"${WORK}/bin/sudo" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"${CALLS}"
EOF
  cat >"${WORK}/bin/gamemoded" <<EOF
#!/usr/bin/env bash
case "\$1" in
  -s4242)
    if [ "\${GM_REGISTERED:-1}" = 1 ]; then
      echo "gamemode is active and [4242] registered"
    else
      echo "gamemode is inactive"
    fi ;;
  -r*) echo "\$1" >>"${GM_CALLS}" ;;
esac
EOF
  chmod +x "${WORK}/bin/"*
  export PATH="${WORK}/bin:${PATH}"
}

teardown() {
  rm -rf "$WORK"
}

@test "steam up with ollama running stops ollama and records that the guard did it" {
  STEAM_UP=1 OLLAMA_UP=1 run "$GUARD" --once

  [ "$status" -eq 0 ]
  [ "$(cat "$CALLS")" = "-n systemctl stop ollama" ]
  [ -e "$STEAM_VRAM_GUARD_STATE" ]
}

@test "steam up with ollama already stopped does nothing and claims nothing" {
  STEAM_UP=1 OLLAMA_UP=0 run "$GUARD" --once

  [ "$status" -eq 0 ]
  [ ! -e "$CALLS" ]
  [ ! -e "$STEAM_VRAM_GUARD_STATE" ]
}

@test "steam gone after the guard stopped ollama starts it again and clears the record" {
  touch "$STEAM_VRAM_GUARD_STATE"

  STEAM_UP=0 OLLAMA_UP=0 run "$GUARD" --once

  [ "$status" -eq 0 ]
  [ "$(cat "$CALLS")" = "-n systemctl start ollama" ]
  [ ! -e "$STEAM_VRAM_GUARD_STATE" ]
}

@test "steam gone with no record leaves a hand-stopped ollama stopped" {
  STEAM_UP=0 OLLAMA_UP=0 run "$GUARD" --once

  [ "$status" -eq 0 ]
  [ ! -e "$CALLS" ]
}

@test "steam still up after a hand restart of ollama does not stop it again" {
  touch "$STEAM_VRAM_GUARD_STATE"

  STEAM_UP=1 OLLAMA_UP=1 run "$GUARD" --once

  [ "$status" -eq 0 ]
  [ ! -e "$CALLS" ]
  [ -e "$STEAM_VRAM_GUARD_STATE" ]
}

@test "steam up and not yet under gamemode registers the steam pid" {
  STEAM_UP=1 OLLAMA_UP=0 GM_REGISTERED=0 run "$GUARD" --once

  [ "$status" -eq 0 ]
  [ "$(cat "$GM_CALLS")" = "-r4242" ]
}

@test "steam already under gamemode is not toggled, which would end gamemode" {
  STEAM_UP=1 OLLAMA_UP=0 GM_REGISTERED=1 run "$GUARD" --once

  [ "$status" -eq 0 ]
  [ ! -e "$GM_CALLS" ]
}

@test "steam gone never asks gamemode for anything" {
  STEAM_UP=0 OLLAMA_UP=0 GM_REGISTERED=0 run "$GUARD" --once

  [ "$status" -eq 0 ]
  [ ! -e "$GM_CALLS" ]
}
