#!/usr/bin/env bash
set -euo pipefail

# Check if autologin is enabled
if grep -q "AutomaticLoginEnable=true" /etc/gdm3/custom.conf 2>/dev/null; then
    # Disable remote login mode
    sudo sed -i 's/AutomaticLoginEnable=true/AutomaticLoginEnable=false/' /etc/gdm3/custom.conf
    sudo systemctl disable tailscale-up.service 2>/dev/null || true
    echo "Remote login mode: OFF"
else
    # Enable remote login mode
    sudo mkdir -p /etc/gdm3
    sudo tee /etc/gdm3/custom.conf > /dev/null << EOF
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=decoder
EOF

    sudo systemctl enable tailscale-up.service
    echo "Remote login mode: ON"
    echo "Tailscale IP: $(tailscale ip -4 2>/dev/null || echo 'pending reboot')"
fi
