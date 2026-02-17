#!/usr/bin/env bash
set -eo pipefail

# Diagnose external display/projector connection issues
# Reads system state and suggests commands to run — does NOT modify anything

echo "=== Display Outputs ==="
xrandr | grep -E "connected|disconnected"
echo ""

echo "=== Active Monitors ==="
xrandr --listmonitors
echo ""

echo "=== GPU Providers ==="
xrandr --listproviders
echo ""

echo "=== Graphics Mode ==="
if command -v system76-power &>/dev/null; then
	system76-power graphics
else
	echo "(system76-power not found)"
fi
echo ""

echo "=== NVIDIA Status ==="
if command -v nvidia-smi &>/dev/null; then
	nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null || echo "nvidia-smi failed"
else
	echo "(nvidia-smi not found)"
fi
echo ""

echo "=== Recent Display Kernel Messages ==="
dmesg --time-format reltime 2>/dev/null | grep -iE "hdmi|dp |edid|drm|display|monitor" | tail -10
echo ""

echo "=== Suggestions ==="

# Check for disconnected outputs that might be the projector
disconnected=$(xrandr | grep "disconnected" | awk '{print $1}')
connected=$(xrandr | grep " connected" | awk '{print $1}')

if [[ -z "$disconnected" ]]; then
	echo "All outputs are connected. If projector isn't showing:"
	echo "  - Check cable/adapter physically"
	echo "  - Try a different port"
	echo ""
fi

for output in $disconnected; do
	echo "Output $output is disconnected. To force enable:"
	echo "  xrandr --output $output --auto"
	echo "  xrandr --output $output --auto --same-as $connected"
	echo ""
done

# Check graphics mode
if command -v system76-power &>/dev/null; then
	mode=$(system76-power graphics 2>/dev/null)
	if [[ "$mode" == "nvidia" ]]; then
		echo "Graphics mode: NVIDIA-only. If laptop panel needed too:"
		echo "  sudo system76-power graphics hybrid"
		echo "  (requires reboot)"
		echo ""
	fi
fi

# Check if only one provider (no iGPU)
provider_count=$(xrandr --listproviders | head -1 | grep -oP '\d+')
if [[ "$provider_count" == "1" ]]; then
	echo "Only one GPU provider active. Some outputs may be on the other GPU."
	echo "If using NVIDIA-only mode, HDMI/DP are on NVIDIA, eDP may need hybrid mode."
	echo ""
fi

# Mirror mode suggestion
if [[ $(xrandr --listmonitors | head -1 | grep -oP '\d+') -ge 2 ]]; then
	primary=$(xrandr | grep "primary" | awk '{print $1}')
	others=$(xrandr | grep " connected" | grep -v "primary" | awk '{print $1}')
	for other in $others; do
		echo "To mirror $primary onto $other:"
		echo "  xrandr --output $other --auto --same-as $primary"
		echo ""
		echo "To extend $primary with $other below:"
		echo "  xrandr --output $other --auto --below $primary"
		echo ""
	done
fi

echo "=== Quick Fixes ==="
echo "Toggle display mode (cycles mirror/extend/external):  Super+P"
echo "Reset all outputs to auto:  xrandr --auto"
echo "Force HDMI on:  xrandr --output HDMI-0 --auto"
echo "Force DP on:    xrandr --output DP-0 --auto"
