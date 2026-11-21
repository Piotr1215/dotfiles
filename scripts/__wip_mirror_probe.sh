#!/usr/bin/env bash
# Prove the real-time WIP mirror still copies new saves (Piotr1215/claude#224).
# The drill and the status row read copies already on the drive, so a mirror
# that stopped copying stayed green all day on 21 Nov. This saves a nonce into
# a probe file under ~/dev and waits for the drive copy to hold it.
#
# Exit 0 with a success stamp when the copy arrives, 1 (and an ntfy page once a
# day) when it does not, 0 without a stamp while wip-mirror.service is not enabled
# or the drive is not mounted (serval away from it; the drive job pages for that).
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/__lib_backup_guard.sh"

DRIVE_MOUNT="${DRIVE_MOUNT:-/mnt/nvme-backup}"
WIP_MIRROR_DIR="${WIP_MIRROR_DIR:-wip}"
PROBE_FILE="${WIP_PROBE_FILE:-$HOME/dev/.wip-mirror-probe}"
PROBE_TIMEOUT="${WIP_PROBE_TIMEOUT:-60}"
STATE_DIR="${WIP_PROBE_STATE_DIR:-$HOME/.local/state/wip-probe}"
NTFY_URL="${BACKUP_NTFY_URL:-https://ntfy.sh/homelab-piotr1215-backup}"

# Page ntfy once a day per cause; the 5-minute probe keeps checking meanwhile.
alert_failure() {
	local text="$1"
	alert_due "$STATE_DIR/alert" "$text" 2>/dev/null || return 0
	curl -fsS -m 20 -H "Priority: high" -H "Tags: warning" \
		-d "serval: WIP mirror stalled: $text" "$NTFY_URL" >/dev/null || echo "ntfy alert failed" >&2
}

main() {
	local nonce copy deadline
	if ! systemctl is-enabled --quiet wip-mirror.service 2>/dev/null; then
		echo "wip-mirror.service not enabled; nothing to probe"
		return 0
	fi
	if ! mountpoint -q "$DRIVE_MOUNT"; then
		echo "drive not mounted at $DRIVE_MOUNT; the drive job pages for that"
		return 0
	fi
	mkdir -p "$STATE_DIR" "$(dirname "$PROBE_FILE")"
	nonce="$(date +%s%N)"
	copy="$DRIVE_MOUNT/$WIP_MIRROR_DIR/live$(realpath -m "$PROBE_FILE")"
	printf '%s\n' "$nonce" >"$PROBE_FILE"
	deadline=$((SECONDS + PROBE_TIMEOUT))
	while ((SECONDS < deadline)); do
		if [[ "$(cat "$copy" 2>/dev/null)" == "$nonce" ]]; then
			date +%s >"$STATE_DIR/last-success"
			echo "probe reached the drive in about $((SECONDS - deadline + PROBE_TIMEOUT)) s"
			return 0
		fi
		sleep 1
	done
	echo "probe not on the drive after ${PROBE_TIMEOUT} s: $copy" >&2
	alert_failure "a save in ~/dev did not reach the drive within ${PROBE_TIMEOUT} s"
	return 1
}

main "$@"
