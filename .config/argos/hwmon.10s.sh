#!/usr/bin/env bash
set -eo pipefail

# CPU package temp
pkg_temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
pkg_temp=$((pkg_temp / 1000))

# Fan speeds
fan1=$(cat /sys/devices/platform/system76/hwmon/hwmon*/fan1_input 2>/dev/null || echo 0)
fan2=$(cat /sys/devices/platform/system76/hwmon/hwmon*/fan2_input 2>/dev/null || echo 0)

# EPP
epp=$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null || echo "unknown")

# GPU temp + power
gpu_temp=""
gpu_power=""
if command -v nvidia-smi &>/dev/null; then
    gpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "")
    gpu_power=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "")
fi

color_for_temp() {
    local t=$1
    if [ "$t" -gt 80 ]; then echo "#ff4444"
    elif [ "$t" -gt 65 ]; then echo "#ff9900"
    else echo "#44ff44"; fi
}

color_for_fan() {
    local rpm=$1
    if [ "$rpm" -gt 3500 ]; then echo "#ff4444"
    elif [ "$rpm" -gt 2500 ]; then echo "#ff9900"
    elif [ "$rpm" -gt 0 ]; then echo "#44ff44"
    else echo "#666666"; fi
}

color_for_epp() {
    case "$1" in
        balance_power|power) echo "#44ff44" ;;
        balance_performance) echo "#ff9900" ;;
        performance) echo "#ff4444" ;;
        *) echo "#666666" ;;
    esac
}

temp_color=$(color_for_temp "$pkg_temp")
fan1_color=$(color_for_fan "$fan1")
fan2_color=$(color_for_fan "$fan2")
epp_color=$(color_for_epp "$epp")

# Panel line
echo "<tt><b>T:</b></tt><tt><span color='${temp_color}'>${pkg_temp}C</span></tt> | font='monospace' size=12 dropdown=false"

# Dropdown
echo "---"
echo "<b>CPU</b> | size=11"
echo "  Package: ${pkg_temp}°C | size=10 color=${temp_color}"
echo "  EPP: ${epp} | size=10 color=${epp_color}"
echo "---"
echo "<b>Fans</b> | size=11"
echo "  CPU: ${fan1} RPM | size=10 color=${fan1_color}"
echo "  GPU: ${fan2} RPM | size=10 color=${fan2_color}"
if [ -n "$gpu_temp" ]; then
    gpu_temp_color=$(color_for_temp "$gpu_temp")
    gpu_power_int=${gpu_power%.*}
    if [ "${gpu_power_int:-0}" -gt 150 ]; then gpu_power_color="#ff4444"
    elif [ "${gpu_power_int:-0}" -gt 80 ]; then gpu_power_color="#ff9900"
    else gpu_power_color="#44ff44"; fi
    echo "---"
    echo "<b>GPU</b> | size=11"
    echo "  Temp: ${gpu_temp}°C | size=10 color=${gpu_temp_color}"
    echo "  Power: ${gpu_power}W | size=10 color=${gpu_power_color}"
fi
echo "---"
echo "Set EPP balance_power | bash='sudo bash -c \"for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do echo balance_power > \\\$f; done\"' terminal=false refresh=true"
echo "Set EPP balance_performance | bash='sudo bash -c \"for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do echo balance_performance > \\\$f; done\"' terminal=false refresh=true"
echo "---"
echo "Refresh | refresh=true"
