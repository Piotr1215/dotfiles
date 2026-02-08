#!/usr/bin/env bash
set -eo pipefail

status=$(tailscale status --json 2>/dev/null) || { echo '{"text":"󰒎 off","tooltip":"tailscale not running"}'; exit 0; }
online=$(echo "$status" | jq -r '.Self.Online')
hostname=$(echo "$status" | jq -r '.Self.HostName')
ip=$(echo "$status" | jq -r '.Self.TailscaleIPs[0] // "?"')
peers=$(echo "$status" | jq '[.Peer | to_entries[] | select(.value.Online == true and .value.ExitNodeOption == false)] | length')

if [[ "$online" == "true" ]]; then
    text="󰒒 ${hostname}"
    tooltip="${ip} | ${peers} peers online"
else
    text="󰒎 off"
    tooltip="tailscale disconnected"
fi

echo "{\"text\":\"${text}\",\"tooltip\":\"${tooltip}\"}"
