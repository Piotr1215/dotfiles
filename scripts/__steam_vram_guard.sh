#!/usr/bin/env bash
# Dedicate the machine to Steam and games while a Steam client runs:
# - stop the system Ollama service so its models leave VRAM, and start it again
#   once Steam exits, but only when this guard was the one that stopped it, so a
#   hand-stopped Ollama stays stopped;
# - register the Steam client with GameMode, so the ~/.config/gamemode.ini knobs
#   apply for the whole Steam session and not only while EVE runs. GameMode's
#   reaper drops the registration by itself when the Steam process exits;
# - hold the system76-power battery profile, Piotr's gaming profile, for the
#   whole session, re-applying it when the EVE wrapper restores balanced on its
#   last client exit. Balanced comes back when Steam exits. GameMode alone ran
#   an idle Steam at 88C package (2026-10-01). The guard never writes CPU sysfs
#   itself: EVE's max_perf_pct 60 plus turbo re-raise is measured for four EVE
#   clients and lives in the EVE wrapper, and holding it for every game ran a
#   non-EVE shader compile at 86C.
#
# Usage: __steam_vram_guard.sh          poll forever (the user service runs this)
#        __steam_vram_guard.sh --once   one check, for tests and manual runs
set -eo pipefail

state_file="${STEAM_VRAM_GUARD_STATE:-${XDG_RUNTIME_DIR:-/tmp}/steam-vram-guard.stopped}"
thermal_state="${STEAM_VRAM_GUARD_THERMAL_STATE:-${XDG_RUNTIME_DIR:-/tmp}/steam-vram-guard.thermal}"
interval="${STEAM_VRAM_GUARD_INTERVAL:-2}"

# Print the pid of this user's Steam client, or nothing when Steam is not running.
steam_pid() {
  pgrep -u "$(id -u)" -x steam | head -n 1 || true
}

# Register a pid with GameMode unless it already is. gamemoded -r toggles, so
# asking twice would end GameMode for that process.
gamemode_register() {
  local pid="$1"
  if ! gamemoded -s"$pid" | grep -qF "[$pid] registered"; then
    gamemoded -r"$pid" >/dev/null
    echo "steam $pid registered with gamemode"
  fi
}

# Hold the battery profile. The output is captured before matching because
# system76-power panics on a closed pipe.
thermal_engage() {
  local profile
  profile="$(system76-power profile 2>/dev/null || true)"
  if [[ "$profile" != *"Power Profile: Battery"* ]]; then
    system76-power profile battery >/dev/null
    echo "steam up, battery profile applied"
  fi
  touch "$thermal_state"
}

# One reconcile step between Steam's state, Ollama's, GameMode's, and the CPU's.
guard_tick() {
  local pid
  pid="$(steam_pid)"
  if [[ -n "$pid" ]]; then
    if [[ ! -e "$state_file" ]] && systemctl is-active --quiet ollama; then
      sudo -n systemctl stop ollama
      touch "$state_file"
      echo "steam up, ollama stopped"
    fi
    gamemode_register "$pid"
    thermal_engage
    return
  fi
  if [[ -e "$state_file" ]]; then
    sudo -n systemctl start ollama
    rm -f "$state_file"
    echo "steam gone, ollama started"
  fi
  if [[ -e "$thermal_state" ]]; then
    system76-power profile balanced >/dev/null
    rm -f "$thermal_state"
    echo "steam gone, balanced profile restored"
  fi
}

main() {
  if [[ "${1:-}" == "--once" ]]; then
    guard_tick
    return
  fi
  while true; do
    guard_tick || echo "guard tick failed, retrying" >&2
    sleep "$interval"
  done
}

main "$@"
