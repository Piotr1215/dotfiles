#!/usr/bin/env bash
# Set the system timezone from the public IP on every network change.
#
# GNOME's automatic timezone rides on geoclue, and on this build (2.7.0) every
# lookup geoclue can make goes to Mozilla's location service, dead since 2024.
# The clock therefore stayed on Europe/Berlin in Corfu. This asks ipinfo.io for
# the timezone of the public IP, which sends nothing but the IP, and sets it
# when it differs from the current one. It leaves the zone alone behind a
# NetworkManager VPN or a Tailscale exit node, where the IP says where the exit
# is, not where the laptop is.
#
# Runs as a NetworkManager dispatcher script (args: interface, action) and by
# hand with no args. NM only runs root-owned files from dispatcher.d, so it is
# installed as a copy, not a symlink:
#   sudo install -m 755 -o root -g root scripts/__auto_timezone.sh \
#     /etc/NetworkManager/dispatcher.d/90-auto-timezone
set -eo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

action="${2:-up}"
case "$action" in up | connectivity-change) ;; *) exit 0 ;; esac

lookup_url="${AUTO_TIMEZONE_URL:-https://ipinfo.io/timezone}"
zoneinfo="${AUTO_TIMEZONE_ZONEINFO:-/usr/share/zoneinfo}"

log() {
	logger -t auto-timezone "$*"
}

# True when the public IP belongs to a VPN or exit node rather than this desk.
vpn_active() {
	if nmcli -t -f TYPE,STATE con show --active 2>/dev/null | grep -Eq '^(vpn|wireguard):activated'; then
		return 0
	fi
	if tailscale status --json 2>/dev/null | grep -Eq '"ExitNodeStatus": *\{'; then
		return 0
	fi
	return 1
}

if vpn_active; then
	log "vpn or exit node active, timezone left alone"
	exit 0
fi

zone=$(curl -fsS --max-time 8 "$lookup_url" 2>/dev/null | tr -d '[:space:]') || zone=""
if [[ -z "$zone" ]]; then
	log "timezone lookup failed"
	exit 0
fi
if ! [[ "$zone" =~ ^[A-Za-z_]+(/[A-Za-z0-9_+-]+)+$ && -f "$zoneinfo/$zone" ]]; then
	log "lookup returned no usable zone: '$zone'"
	exit 0
fi

current=$(timedatectl show -p Timezone --value)
[[ "$zone" == "$current" ]] && exit 0

timedatectl set-timezone "$zone"
log "timezone $current -> $zone"
