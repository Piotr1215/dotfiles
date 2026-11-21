#!/usr/bin/env bash
# PROJECT: graphics-mode-aliases
#
# Switch system76 graphics mode, power profile and lid behaviour, then shut down, so
# the next manual power-on lands in the mode.
#
# Modes (one function per mode — extend freely):
#   base   powered: nvidia GPU, balanced profile, lid ignored (home, hotel, anywhere on AC)
#   speak  presenting: hybrid GPU, battery profile, lid suspends on battery and on power
#
# Usage: __set_graphics_mode.sh <base|speak> [--reboot] [--no-shutdown] [--yes]
#   --reboot       reboot instead of shutting down
#   --no-shutdown  apply settings and leave the machine on
#   --yes / -y     skip confirmation prompt
#
# Note: `system76-power graphics` writes to /etc/modprobe.d and needs sudo.
#       `system76-power profile` runs as user (matches existing `perf` alias).
#       HandleLidSwitch and HandleLidSwitchExternalPower live in logind.conf, need sudo,
#       and take effect at the next boot.

set -eo pipefail

LOGIND_CONF="${LOGIND_CONF:-/etc/systemd/logind.conf}"

usage() {
  cat >&2 <<EOF
usage: $(basename "$0") <base|speak> [--reboot] [--no-shutdown] [--yes]

  base   nvidia + balanced, lid ignored   (powered: home, hotel, anywhere on AC)
  speak  hybrid  + battery, lid suspends  (presenting, on battery or plugged in)
  login  restore the battery profile when graphics is hybrid
  check  report whether the current mode settings agree

  --reboot       reboot instead of shutting down
  --no-shutdown  apply settings and leave the machine on
  --yes, -y      skip confirmation prompt
EOF
  exit 1
}

# Switch graphics mode. Requires sudo. Takes effect at the next boot.
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

# Set what closing the lid does, on battery and plugged in alike: a talk usually runs on
# the venue's power. Requires sudo. Fails rather than power down on a setting that did
# not land, so a dock never comes back with the lid in the wrong state.
# Arg: $1 = suspend|ignore
apply_lid() {
  local action="$1" key
  echo ">>> HandleLidSwitch=${action} HandleLidSwitchExternalPower=${action}"
  sudo sed -i -E -e "s/^#?HandleLidSwitch=.*/HandleLidSwitch=${action}/" \
    -e "s/^#?HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=${action}/" "$LOGIND_CONF"
  for key in HandleLidSwitch HandleLidSwitchExternalPower; do
    grep -qx "${key}=${action}" "$LOGIND_CONF" || {
      echo "no ${key} line in ${LOGIND_CONF}" >&2
      exit 1
    }
  done
}

# Mode: powered — enforce nvidia graphics, balanced power.
# Covers home/docked, hotel on AC, conference hallway plugged in, EVE travel night.
mode_base() {
  apply_graphics nvidia
  apply_profile balanced
  apply_lid ignore
  # extend here: e.g., set EPP, fan curve, mount NAS, etc.
}

# Mode: presenting — enforce hybrid graphics + battery profile.
# Hybrid is mandatory: HDMI is wired to the dGPU on serw14, and presenting
# always involves a projector/beamer over HDMI. Do NOT switch this to
# `integrated` — that kills HDMI output. The dGPU should sleep when no display
# is connected to it.
# Battery profile caps CPU max_perf_pct and disables turbo — saves 5–10W vs
# balanced, the single biggest lever toward the 3h target. If you need turbo
# for a specific moment, run `perf` to override.
mode_speak() {
  apply_graphics hybrid
  apply_profile battery
  apply_lid suspend
  # extend here: e.g., dim brightness, mute audio, pre-pull demo images.
}

# The system76-power daemon resets the profile to balanced on start, so restore
# battery after the boot that applies speak's hybrid graphics.
mode_login() {
  local graphics speak_flag="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/speak-mode"
  graphics=$(system76-power graphics 2>/dev/null) || return 0
  if [[ "$graphics" == hybrid ]]; then
    touch "$speak_flag" || true
    apply_profile battery || true
  else
    rm -f "$speak_flag" || true
  fi
  return 0
}

# Report an awake NVIDIA display controller only when all its outputs are disconnected.
check_nvidia_runtime() {
  local pci connector pci_path connector_path vendor class runtime status
  local found all_disconnected
  for pci in "${SYSFS_PCI:-/sys/bus/pci/devices}"/*; do
    [[ -r "$pci/vendor" && -r "$pci/class" && -r "$pci/power/runtime_status" ]] || continue
    read -r vendor < "$pci/vendor" || continue
    read -r class < "$pci/class" || continue
    [[ "$vendor" == 0x10de && "$class" == 0x03???? ]] || continue
    read -r runtime < "$pci/power/runtime_status" || continue
    [[ "$runtime" != suspended ]] || continue
    pci_path=$(readlink -e "$pci") || continue
    found=0; all_disconnected=1
    for connector in "${SYSFS_DRM:-/sys/class/drm}"/card*-*; do
      [[ -e "$connector/device" ]] || continue
      connector_path=$(readlink -e "$connector/device") || continue
      if [[ "$connector_path" != "$pci_path" ]]; then
        connector_path=$(readlink -e "$connector/device/device") || continue
        [[ "$connector_path" == "$pci_path" ]] || continue
      fi
      found=1
      if [[ ! -r "$connector/status" ]] || ! read -r status < "$connector/status" || [[ "$status" != disconnected ]]; then
        all_disconnected=0
      fi
    done
    if (( found && all_disconnected )); then
      printf '%s\n' "NVIDIA GPU awake (runtime_status $runtime) with no display on it"
    fi
  done
  return 0
}

# Report every setting that disagrees with the active graphics mode.
mode_check() {
  local graphics profile profile_output expected_profile expected_lid mode key line value gpu_mismatch
  local lid="missing" lid_external="missing"
  local speak_flag="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/speak-mode"
  local -a wrong=()

  graphics=$(system76-power graphics 2>/dev/null) || graphics="unavailable"
  profile_output=$(system76-power profile 2>/dev/null) || profile_output="unavailable"
  profile="${profile_output%%$'\n'*}"
  if [[ "$profile" == 'Power Profile: '* ]]; then
    profile="${profile#Power Profile: }"
  else
    profile="unavailable"
  fi

  case "$graphics" in
    hybrid) mode=speak; expected_profile=Battery; expected_lid=suspend ;;
    nvidia) mode=base; expected_profile=Balanced; expected_lid=ignore ;;
    *) mode="$graphics"; wrong+=("graphics=$graphics") ;;
  esac

  if [[ -n "${expected_profile:-}" ]]; then
    [[ "$profile" == "$expected_profile" ]] || wrong+=("profile=$profile (expected $expected_profile)")
    if [[ "$mode" == speak && ! -e "$speak_flag" ]]; then
      wrong+=("speak-flag=absent (expected present)")
    elif [[ "$mode" == base && -e "$speak_flag" ]]; then
      wrong+=("speak-flag=present (expected absent)")
    fi

    if [[ -r "$LOGIND_CONF" ]]; then
      while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]*(HandleLidSwitch|HandleLidSwitchExternalPower)[[:space:]]*=[[:space:]]*([^[:space:]]*)[[:space:]]*$ ]]; then
          key="${BASH_REMATCH[1]}"; value="${BASH_REMATCH[2]}"
          case "$key" in
            HandleLidSwitch) lid="$value" ;;
            HandleLidSwitchExternalPower) lid_external="$value" ;;
          esac
        fi
      done < "$LOGIND_CONF"
    fi
    [[ "$lid" == "$expected_lid" ]] || wrong+=("HandleLidSwitch=$lid (expected $expected_lid)")
    [[ "$lid_external" == "$expected_lid" ]] || wrong+=("HandleLidSwitchExternalPower=$lid_external (expected $expected_lid)")
    if [[ "$mode" == speak ]]; then
      while IFS= read -r gpu_mismatch; do
        [[ -z "$gpu_mismatch" ]] || wrong+=("$gpu_mismatch")
      done < <(check_nvidia_runtime)
    fi
  elif [[ "$profile_output" == unavailable ]]; then
    wrong+=("profile=unavailable")
  fi

  if (( ${#wrong[@]} )); then
    printf '%s\n' "mode $mode mismatch: ${wrong[*]}"
    return 1
  fi
  printf '%s\n' "mode $mode ok"
}

main() {
  if [[ "${1:-}" == login ]]; then
    mode_login
    return 0
  fi
  if [[ "${1:-}" == check ]]; then
    mode_check
    return $?
  fi

  local mode=""
  local after="poweroff"
  local skip_confirm=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      base|speak)      mode="$1" ;;
      --reboot)        after="reboot" ;;
      --no-shutdown)   after="none" ;;
      -y|--yes)        skip_confirm=1 ;;
      -h|--help)       usage ;;
      *) echo "unknown arg: $1" >&2; usage ;;
    esac
    shift
  done

  [[ -n "$mode" ]] || usage

  echo ">>> mode: ${mode}"
  if [[ $skip_confirm -eq 0 ]]; then
    local prompt=">>> apply and ${after}? [y/N] "
    [[ "$after" == none ]] && prompt=">>> apply and stay on? [y/N] "
    read -r -p "$prompt" reply
    [[ "$reply" =~ ^[Yy]$ ]] || { echo "aborted."; exit 0; }
  fi

  case "$mode" in
    base)  mode_base ;;
    speak) mode_speak ;;
  esac

  if [[ "$after" == none ]]; then
    echo ">>> done. the graphics and lid changes take effect at the next boot."
  else
    sync
    echo ">>> ${after}..."
    sudo "$after"
  fi
}

main "$@"
