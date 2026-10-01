#!/usr/bin/env bash
# Dedicate the machine to Steam and games while a Steam client runs:
# - stop the system Ollama service so its models leave VRAM, and start it again
#   once Steam exits, but only when this guard was the one that stopped it, so a
#   hand-stopped Ollama stays stopped;
# - register the Steam client with GameMode, so the ~/.config/gamemode.ini knobs
#   apply for the whole Steam session and not only while EVE runs. GameMode's
#   reaper drops the registration by itself when the Steam process exits.
#
# Usage: __steam_vram_guard.sh          poll forever (the user service runs this)
#        __steam_vram_guard.sh --once   one check, for tests and manual runs
set -eo pipefail

state_file="${STEAM_VRAM_GUARD_STATE:-${XDG_RUNTIME_DIR:-/tmp}/steam-vram-guard.stopped}"
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

# One reconcile step between Steam's state, Ollama's, and GameMode's.
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
  elif [[ -e "$state_file" ]]; then
    sudo -n systemctl start ollama
    rm -f "$state_file"
    echo "steam gone, ollama started"
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
