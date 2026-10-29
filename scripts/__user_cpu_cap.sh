#!/usr/bin/env bash
set -euo pipefail
usage() { echo 'usage: __user_cpu_cap.sh on|off|status|recovery' >&2; }
[[ $# -eq 1 ]] || { usage; exit 2; }
cores=$(nproc --all)
case "$1" in
  status)
    file=${USER_CPU_CAP_CGROUP_FILE:-/sys/fs/cgroup/user.slice/cpu.max}
    if ! read -r quota period extra < "$file" || [[ -n ${extra:-} || ! $period =~ ^[0-9]+$ || $period -eq 0 ]]; then
      echo 'CPU cap status unavailable' >&2; exit 2
    fi
    if [[ $quota == max ]]; then echo 'CPU cap off'; exit 1; fi
    if [[ ! $quota =~ ^[0-9]+$ ]]; then echo 'CPU cap status unavailable' >&2; exit 2; fi
    if (( quota * 100 == period * cores * 80 )); then echo 'CPU cap on'; exit 0; fi
    echo "CPU cap differs from 80%: $quota $period"; exit 2
    ;;
  on|off)
    if [[ $1 == on ]]; then
      sudo systemctl set-property user.slice CPUQuota=1920%
    else
      sudo systemctl set-property user.slice CPUQuota=
    fi
    # Only remove interim quotas that match the fleet cap we installed earlier.
    micros=$((cores * 800000))
    expected=$(printf '%d.%06ds' "$((micros / 1000000))" "$((micros % 1000000))")
    units=(app.slice)
    server_pid=$(tmux display-message -p '#{pid}' 2>/dev/null || true)
    if [[ $server_pid =~ ^[0-9]+$ && -r /proc/$server_pid/cgroup ]]; then
      scope=$(sed -n 's|.*\/\(app-gnome-__boot\.sh-[0-9]*\.scope\)$|\1|p' "/proc/$server_pid/cgroup")
      [[ -z $scope ]] || units+=("$scope")
    fi
    for unit in "${units[@]}"; do
      actual=$(systemctl --user show "$unit" -p CPUQuotaPerSecUSec --value 2>/dev/null || true)
      if [[ $actual == "$expected" ]]; then
        systemctl --user set-property --runtime "$unit" 'CPUQuota='
      fi
    done
    ;;
  # A clean shell avoids startup files attaching back to the capped tmux server.
  recovery) exec systemd-run --user --scope --slice=session.slice -p CPUWeight=10000 alacritty --title 'CPU recovery' -e /usr/bin/bash --noprofile --norc ;;
  *) usage; exit 2 ;;
esac
