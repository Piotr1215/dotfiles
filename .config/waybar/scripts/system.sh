#!/usr/bin/env bash
set -eo pipefail

# CPU
if command -v mpstat &>/dev/null; then
	cpu_idle=$(mpstat 1 1 | awk '/Average:/ {print $(NF)}')
	cpu=${cpu_idle:+$(printf "%.0f" "$(echo "100 - $cpu_idle" | bc)")}
	cpu=${cpu:-0}
else
	cpu=0
fi

# GPU
gpu="N/A"
gpu_color="#666666"
if command -v nvidia-smi &>/dev/null; then
	g=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1)
	if [[ "$g" =~ ^[0-9]+$ ]]; then
		gpu="${g}%"
		if ((g > 80)); then gpu_color="#ff4444"
		elif ((g > 50)); then gpu_color="#ff9900"
		else gpu_color="#44ff44"; fi
	fi
fi

# RAM
mem=$(free | awk '/^Mem:/ {printf "%.0f", ($3/$2)*100}')

# Colors
if ((cpu > 90)); then cpu_color="#ff4444"
elif ((cpu > 70)); then cpu_color="#ff9900"
else cpu_color="#44ff44"; fi

if ((mem > 90)); then mem_color="#ff4444"
elif ((mem > 70)); then mem_color="#ff9900"
else mem_color="#44ff44"; fi

text="CPU <span color='${cpu_color}'>${cpu}%</span>  GPU <span color='${gpu_color}'>${gpu}</span>  RAM <span color='${mem_color}'>${mem}%</span>"
printf '{"text": "%s"}\n' "$text"
