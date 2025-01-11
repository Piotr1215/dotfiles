#!/usr/bin/env bash
set -euo pipefail

SOCKET_DIR="${HOME}/.mpv_sockets"

function clean_stale_sockets() {
	for socket in "${SOCKET_DIR}"/*.sock; do
		if [[ -S "$socket" ]] && ! socat -u OPEN:/dev/null UNIX-CONNECT:"$socket" 2>/dev/null; then
			rm -f "$socket"
		fi
	done
}

function send_mpv_command() {
	local command="$1"
	clean_stale_sockets

	local sockets=("${SOCKET_DIR}"/*.sock)
	if [[ ! -d "$SOCKET_DIR" ]] || [[ ${#sockets[@]} -eq 0 ]]; then
		echo "No active MPV sockets found"
		exit 1
	fi

	for socket in "${sockets[@]}"; do
		if [[ -S "$socket" ]]; then
			if echo '{ "command": ['$command'], "request_id": 123 }' | socat - "$socket" 2>/dev/null; then
				echo "Sent command to: $(basename "$socket")"
			fi
		fi
	done
}

case "${1:-help}" in
"toggle")
	send_mpv_command '"cycle", "pause"'
	;;
"stop")
	send_mpv_command '"stop"'
	;;
"restart")
	send_mpv_command '"seek", 0, "absolute"'
	;;
"list")
	clean_stale_sockets
	ls -1 "${SOCKET_DIR}"/*.sock 2>/dev/null || echo "No active sockets"
	;;
"help" | *)
	echo "Usage: $(basename "$0") {toggle|stop|restart|list}"
	exit 1
	;;
esac
