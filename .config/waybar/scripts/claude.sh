#!/usr/bin/env bash
set -eo pipefail

mapfile -t lines < <(ps aux | awk '$11 ~ /\/claude$/ || $11 == "claude" {print $2, $3, $6, $9, $7}')
count=${#lines[@]}
orphan_count=0
tooltip=""

for line in "${lines[@]}"; do
	read -r pid cpu mem time tty <<< "$line"
	[[ -z "$pid" ]] && continue
	mem_mb=$((mem / 1024))
	if [[ "$tty" == "?" ]]; then
		((++orphan_count))
		tooltip+="ORPHAN PID $pid  CPU:${cpu}%  Mem:${mem_mb}MB\n"
	else
		tooltip+="PID $pid ($tty)  CPU:${cpu}%  Mem:${mem_mb}MB\n"
	fi
done

if ((orphan_count > 0)); then
	printf '{"text": "C:%d ⚠%d", "tooltip": "%s", "class": "warning"}\n' "$count" "$orphan_count" "$tooltip"
elif ((count > 0)); then
	printf '{"text": "C:%d", "tooltip": "%s", "class": "normal"}\n' "$count" "$tooltip"
else
	printf '{"text": "", "class": "empty"}\n'
fi
