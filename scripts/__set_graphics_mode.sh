#!/usr/bin/env bash
# PROJECT: graphics-mode-aliases
#
# Switch system76 graphics mode + power profile and reboot.
#
# Modes (one function per mode — extend freely):
#   base   powered: nvidia GPU, balanced profile (home, hotel, anywhere on AC)
#   speak  presenting: hybrid GPU, battery profile (HDMI projector on battery)
#
# Usage: __set_graphics_mode.sh <base|speak> [--no-reboot] [--yes]
#   --no-reboot   apply settings but do not reboot
#   --yes / -y    skip confirmation prompt
#
# Note: `system76-power graphics` writes to /etc/modprobe.d and needs sudo.
#       `system76-power profile` runs as user (matches existing `perf` alias).

set -eo pipefail

usage() {
  cat >&2 <<EOF
usage: $(basename "$0") <base|speak> [--no-reboot] [--yes]

  base   nvidia + balanced  (powered: home, hotel, anywhere on AC)
  speak  hybrid  + battery  (presenting: HDMI projector on battery)

  --no-reboot   apply settings but do not reboot
  --yes, -y     skip confirmation prompt
EOF
  exit 1
}

# Switch graphics mode. Requires sudo. Reboot needed for change to take effect.
# Arg: $1 = nvidia|hybrid|integrated|compute
apply_graphics() {
  local graphics="$1"
  echo ">>> system76-power graphics ${graphics}"
  sudo system76-power graphics "${graphics}"
}

# Set power profile. No sudo required.
# Arg: $1 = battery|balanced|performance
apply_profile() {
  local profile="$1"
  echo ">>> system76-power profile ${profile}"
  system76-power profile "${profile}"
}

# Mode: powered — enforce nvidia graphics, balanced power.
# Covers home/docked, hotel on AC, conference hallway plugged in, EVE travel night.
mode_base() {
  apply_graphics nvidia
  apply_profile balanced
  # extend here: e.g., set EPP, fan curve, mount NAS, etc.
}

# Mode: presenting — enforce hybrid graphics + battery profile.
# Hybrid is mandatory: HDMI is wired to the dGPU on serw14, and presenting
# always involves a projector/beamer over HDMI. Do NOT switch this to
# `integrated` — that kills HDMI output. Pay the ~5W dGPU PRIME idle floor
# as the cost of having HDMI work on battery.
# Battery profile caps CPU max_perf_pct and disables turbo — saves 5–10W vs
# balanced, the single biggest lever toward the 3h target. If you need turbo
# for a specific moment, run `perf` to override.
mode_speak() {
  apply_graphics hybrid
  apply_profile battery
  # extend here: e.g., dim brightness, mute audio, pre-pull demo images.
}

main() {
  local mode=""
  local do_reboot=1
  local skip_confirm=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      base|speak)      mode="$1" ;;
      --no-reboot)     do_reboot=0 ;;
      -y|--yes)        skip_confirm=1 ;;
      -h|--help)       usage ;;
      *) echo "unknown arg: $1" >&2; usage ;;
    esac
    shift
  done

  [[ -n "$mode" ]] || usage

  echo ">>> mode: ${mode}"
  if [[ $skip_confirm -eq 0 ]]; then
    local prompt=">>> apply and reboot? [y/N] "
    [[ $do_reboot -eq 0 ]] && prompt=">>> apply (no reboot)? [y/N] "
    read -r -p "$prompt" reply
    [[ "$reply" =~ ^[Yy]$ ]] || { echo "aborted."; exit 0; }
  fi

  case "$mode" in
    base)  mode_base ;;
    speak) mode_speak ;;
  esac

  if [[ $do_reboot -eq 1 ]]; then
    sync
    echo ">>> rebooting..."
    sudo reboot
  else
    echo ">>> done. reboot required for graphics mode change to take effect."
  fi
}

main "$@"
