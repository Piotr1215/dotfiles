#!/usr/bin/env bash
set -eo pipefail

# Claude process monitor for Argos
# Alert icon only for detached/orphan processes

# Get claude processes (PID, CPU%, MEM_KB, TIME, TTY)
get_claude_processes() {
    ps aux | awk '$11 ~ /\/claude$/ || $11 == "claude" {print $2, $3, $6, $9, $7}'
}

# Count and collect
mapfile -t lines < <(get_claude_processes)
count=${#lines[@]}
orphan_count=0
orphan_pids=()

# Check for orphans (detached - no tty)
for line in "${lines[@]}"; do
    read -r pid cpu mem time tty <<< "$line"
    if [[ "$tty" == "?" ]]; then
        ((++orphan_count))
        orphan_pids+=("$pid")
    fi
done

# Panel display - alert only for orphans
if (( orphan_count > 0 )); then
    echo "<tt><b>⚠️ C:</b></tt><tt><span color='#ff4444'>$orphan_count orphan</span></tt> | font='monospace' size=12 dropdown=false"
elif (( count > 0 )); then
    echo "<tt><b>C:</b></tt><tt><span color='#888888'>${count}</span></tt> | font='monospace' size=12 dropdown=false"
else
    # No claude running - hide from panel
    echo "| dropdown=false"
    exit 0
fi

echo "---"

for line in "${lines[@]}"; do
    read -r pid cpu mem time tty <<< "$line"
    [[ -z "$pid" ]] && continue

    mem_mb=$((mem / 1024))

    if [[ "$tty" == "?" ]]; then
        echo "<b>⚠️ PID $pid (orphan)</b> | color=#ff4444 size=11"
    else
        echo "<b>PID $pid</b> ($tty) | size=11"
    fi
    echo "  CPU: ${cpu}%  Mem: ${mem_mb}MB  Time: $time | size=10 color=#888888"
    echo "  Kill | bash='kill $pid' terminal=false refresh=true size=10"
    echo "  Kill -9 | bash='kill -9 $pid' terminal=false refresh=true size=10 color=#ff4444"
    echo "---"
done

echo "---"
if (( orphan_count > 0 )); then
    echo "<b>Kill ALL orphans</b> | bash='kill -9 ${orphan_pids[*]}' terminal=false refresh=true color=#ff4444"
fi
echo "Refresh | refresh=true"
