#!/usr/bin/env bats

# __steam_vram_guard.sh frees the GPU for Steam: it stops the system Ollama
# service the moment a Steam client appears, and starts it again once Steam is
# gone, but only when the guard was the one that stopped it. The EVE launch
# wrapper only pauses classif, so Steam's own shader replay and any non-EVE game
# still competed with a resident llama3.2 for VRAM (2026-10-01). It also puts
# the Steam client under GameMode, which until then only EVE launches started.
#
# GameMode alone ran an idle Steam at 88C package: it lifted the governor to
# performance with turbo and no clamp. Steam now holds the system76-power
# battery profile for the whole session and balanced comes back when it exits.
# The guard never writes CPU sysfs: carrying EVE's max_perf_pct 60 plus turbo
# re-raise to every game ran a non-EVE shader compile at 86C. Balanced does not
# clear the battery profile's absolute 2.7GHz ceiling, so after Steam exits the
# guard lifts every policy back to its hardware maximum once turbo is back.

setup() {
  GUARD="${BATS_TEST_DIRNAME}/../../scripts/__steam_vram_guard.sh"
  WORK="$(mktemp -d)"
  CALLS="${WORK}/calls"
  GM_CALLS="${WORK}/gamemode-calls"
  S76_CALLS="${WORK}/system76-calls"
  export STEAM_VRAM_GUARD_STATE="${WORK}/stopped-by-guard"
  export STEAM_VRAM_GUARD_THERMAL_STATE="${WORK}/thermal-engaged"
  export STEAM_VRAM_GUARD_CEILING_STATE="${WORK}/ceiling-pending"

  # A fake sysfs that already holds the EVE values, so only tests that change
  # it expect writes.
  export STEAM_VRAM_GUARD_PSTATE_DIR="${WORK}/intel_pstate"
  export STEAM_VRAM_GUARD_CPUFREQ_DIR="${WORK}/cpufreq"
  mkdir -p "$STEAM_VRAM_GUARD_PSTATE_DIR" "$STEAM_VRAM_GUARD_CPUFREQ_DIR/policy0"
  echo 60 >"$STEAM_VRAM_GUARD_PSTATE_DIR/max_perf_pct"
  echo 0 >"$STEAM_VRAM_GUARD_PSTATE_DIR/no_turbo"
  echo 5400000 >"$STEAM_VRAM_GUARD_CPUFREQ_DIR/policy0/cpuinfo_max_freq"
  echo 5400000 >"$STEAM_VRAM_GUARD_CPUFREQ_DIR/policy0/scaling_max_freq"

  # Stand-ins: pgrep answers from STEAM_UP with pid 4242, systemctl from
  # OLLAMA_UP, gamemoded -s from GM_REGISTERED, system76-power profile from
  # S76_PROFILE. sudo, gamemoded -r and profile changes record the call instead
  # of running it, so no test touches a real unit or a real sysfs file.
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
if [ "\$2" = tee ]; then echo "\$* <- \$(cat)" >>"${CALLS}"; else echo "\$*" >>"${CALLS}"; fi
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
  cat >"${WORK}/bin/system76-power" <<EOF
#!/usr/bin/env bash
if [ "\$*" = profile ]; then
  echo "Power Profile: \${S76_PROFILE:-Battery}"
else
  echo "\$*" >>"${S76_CALLS}"
fi
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

@test "steam up on balanced switches to the battery profile and records it" {
  STEAM_UP=1 S76_PROFILE=Balanced run "$GUARD" --once

  [ "$status" -eq 0 ]
  [ "$(cat "$S76_CALLS")" = "profile battery" ]
  [ -e "$STEAM_VRAM_GUARD_THERMAL_STATE" ]
}

@test "steam up already on battery does not re-apply the profile" {
  STEAM_UP=1 S76_PROFILE=Battery run "$GUARD" --once

  [ "$status" -eq 0 ]
  [ ! -e "$S76_CALLS" ]
  [ -e "$STEAM_VRAM_GUARD_THERMAL_STATE" ]
}

@test "steam up with the battery clamp in place leaves cpu sysfs alone" {
  echo 50 >"$STEAM_VRAM_GUARD_PSTATE_DIR/max_perf_pct"
  echo 1 >"$STEAM_VRAM_GUARD_PSTATE_DIR/no_turbo"
  echo 2700000 >"$STEAM_VRAM_GUARD_CPUFREQ_DIR/policy0/scaling_max_freq"

  STEAM_UP=1 run "$GUARD" --once

  [ "$status" -eq 0 ]
  [ ! -e "$CALLS" ]
}

@test "steam gone after the guard engaged battery restores balanced and clears the record" {
  touch "$STEAM_VRAM_GUARD_THERMAL_STATE"

  STEAM_UP=0 run "$GUARD" --once

  [ "$status" -eq 0 ]
  [ "$(cat "$S76_CALLS")" = "profile balanced" ]
  [ ! -e "$STEAM_VRAM_GUARD_THERMAL_STATE" ]
}

@test "steam gone after the guard engaged battery marks the ceiling for lifting" {
  touch "$STEAM_VRAM_GUARD_THERMAL_STATE"
  echo 1 >"$STEAM_VRAM_GUARD_PSTATE_DIR/no_turbo"

  STEAM_UP=0 run "$GUARD" --once

  [ "$status" -eq 0 ]
  [ -e "$STEAM_VRAM_GUARD_CEILING_STATE" ]
  [ ! -e "$CALLS" ]
}

@test "a pending ceiling with turbo back lifts each policy to its hardware maximum" {
  touch "$STEAM_VRAM_GUARD_CEILING_STATE"
  mkdir -p "$STEAM_VRAM_GUARD_CPUFREQ_DIR/policy1"
  echo 4700000 >"$STEAM_VRAM_GUARD_CPUFREQ_DIR/policy1/cpuinfo_max_freq"
  echo 2700000 >"$STEAM_VRAM_GUARD_CPUFREQ_DIR/policy0/scaling_max_freq"
  echo 2700000 >"$STEAM_VRAM_GUARD_CPUFREQ_DIR/policy1/scaling_max_freq"

  STEAM_UP=0 run "$GUARD" --once

  [ "$status" -eq 0 ]
  grep -qxF -- "-n tee ${STEAM_VRAM_GUARD_CPUFREQ_DIR}/policy0/scaling_max_freq <- 5400000" "$CALLS"
  grep -qxF -- "-n tee ${STEAM_VRAM_GUARD_CPUFREQ_DIR}/policy1/scaling_max_freq <- 4700000" "$CALLS"
  [ ! -e "$STEAM_VRAM_GUARD_CEILING_STATE" ]
}

@test "a pending ceiling waits while turbo is still off, cpuinfo is collapsed then" {
  touch "$STEAM_VRAM_GUARD_CEILING_STATE"
  echo 1 >"$STEAM_VRAM_GUARD_PSTATE_DIR/no_turbo"
  echo 2700000 >"$STEAM_VRAM_GUARD_CPUFREQ_DIR/policy0/scaling_max_freq"

  STEAM_UP=0 run "$GUARD" --once

  [ "$status" -eq 0 ]
  [ ! -e "$CALLS" ]
  [ -e "$STEAM_VRAM_GUARD_CEILING_STATE" ]
}

@test "steam coming back drops a pending ceiling lift, battery owns the ceiling again" {
  touch "$STEAM_VRAM_GUARD_CEILING_STATE"
  echo 2700000 >"$STEAM_VRAM_GUARD_CPUFREQ_DIR/policy0/scaling_max_freq"

  STEAM_UP=1 run "$GUARD" --once

  [ "$status" -eq 0 ]
  [ ! -e "$CALLS" ]
  [ ! -e "$STEAM_VRAM_GUARD_CEILING_STATE" ]
}

@test "steam gone with no thermal record leaves the power profile alone" {
  STEAM_UP=0 S76_PROFILE=Battery run "$GUARD" --once

  [ "$status" -eq 0 ]
  [ ! -e "$S76_CALLS" ]
}

@test "steam gone never writes cpu sysfs values" {
  echo 50 >"$STEAM_VRAM_GUARD_PSTATE_DIR/max_perf_pct"

  STEAM_UP=0 run "$GUARD" --once

  [ "$status" -eq 0 ]
  [ ! -e "$CALLS" ]
}
