#!/usr/bin/env bash
set -eo pipefail

# CPU Usage - using mpstat
get_cpu_usage() {
    if command -v mpstat &> /dev/null; then
        # Get the idle percentage from mpstat and calculate usage
        cpu_idle=$(mpstat 1 1 | awk '/Average:/ {print $(NF)}')
        if [ -z "$cpu_idle" ]; then
            cpu_usage=0
        else
            cpu_usage=$(printf "%.0f" "$(echo "100 - $cpu_idle" | bc)")
        fi
    else
        cpu_usage=0
    fi
    echo $cpu_usage
}

# Get all values
cpu_usage=$(get_cpu_usage)

# GPU Usage
gpu_text="N/A "
gpu_usage=""
if command -v nvidia-smi &> /dev/null; then
    gpu_usage=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "")
    # Only use if it's actually a number (nvidia-smi may output error to stdout)
    if [[ "$gpu_usage" =~ ^[0-9]+$ ]]; then
        gpu_text=$(printf "%3d%%" $gpu_usage)
    else
        gpu_usage=""
    fi
fi

# Memory Usage
mem_percent=$(free | awk '/^Mem:/ {printf "%.0f", ($3/$2)*100}')

# Determine colors
if [ $cpu_usage -gt 90 ]; then
    cpu_color="#ff4444"
elif [ $cpu_usage -gt 70 ]; then
    cpu_color="#ff9900"
else
    cpu_color="#44ff44"
fi

if [ -n "$gpu_usage" ]; then
    if [ "$gpu_usage" -gt 80 ]; then
        gpu_color="#ff4444"
    elif [ "$gpu_usage" -gt 50 ]; then
        gpu_color="#ff9900"
    else
        gpu_color="#44ff44"
    fi
else
    gpu_color="#666666"
fi

if [ $mem_percent -gt 90 ]; then
    mem_color="#ff4444"
elif [ $mem_percent -gt 70 ]; then
    mem_color="#ff9900"
else
    mem_color="#44ff44"
fi

# Format each part with EXACT width using spaces
cpu_formatted=$(printf "%3d%%" $cpu_usage)
mem_formatted=$(printf "%3d%%" $mem_percent)

# Build the single line output with reasonable spacing (3 spaces)
spacing="   "

# Output as ONE LINE with consistent spacing
echo "<tt><b>CPU:</b></tt><tt><span color='${cpu_color}'>${cpu_formatted}</span></tt>${spacing}<tt><b>GPU:</b></tt><tt><span color='${gpu_color}'>${gpu_text}</span></tt>${spacing}<tt><b>RAM:</b></tt><tt><span color='${mem_color}'>${mem_formatted}</span></tt> | font='monospace' size=12 dropdown=false"
