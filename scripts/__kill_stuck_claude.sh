#!/usr/bin/env bash
set -eo pipefail

# Detect and kill stuck Claude processes with high CPU usage
# Usage: __kill_stuck_claude.sh [OPTIONS]
#   -t, --threshold CPU_PERCENT   CPU threshold (default: 80)
#   -a, --auto                    Auto-kill without confirmation
#   -d, --dry-run                 Show what would be killed
#   -h, --help                    Show this help

# Parse command line arguments
parse_args() {
    local cpu_threshold=80
    local auto_kill=false
    local dry_run=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--threshold)
                cpu_threshold="$2"
                shift 2
                ;;
            -a|--auto)
                auto_kill=true
                shift
                ;;
            -d|--dry-run)
                dry_run=true
                shift
                ;;
            -h|--help)
                # Handled in main()
                shift
                ;;
            *)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
        esac
    done

    echo "$cpu_threshold|$auto_kill|$dry_run"
}

# Get Claude processes with high CPU
get_stuck_processes() {
    local threshold=$1
    # Get claude processes with CPU > threshold
    ps aux | awk -v threshold="$threshold" '$11 == "claude" && $3 > threshold {print $2, $3, $6, $9}' | \
    while read -r pid cpu mem time; do
        # Check if process has zombie children
        local zombie_count
        zombie_count=$(ps --ppid "$pid" -o stat= 2>/dev/null | grep -c Z || echo "0")

        # Report process with CPU and zombie info
        echo "$pid|$cpu|$mem|$time|$zombie_count"
    done
}

# Display process details
show_process_details() {
    local pid=$1
    local cpu=$2
    local mem=$3
    local time=$4
    local zombies=$5

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Stuck Claude Process Detected:"
    echo "  PID:     $pid"
    echo "  CPU:     ${cpu}%"
    echo "  Memory:  $(awk -v mem="$mem" 'BEGIN {printf "%.1f GB", mem/1024/1024}')"
    echo "  Runtime: $time"
    echo "  Zombies: $zombies child processes"

    # Show zombie children
    if (( zombies > 0 )); then
        echo ""
        echo "Zombie child processes:"
        ps --ppid "$pid" -o pid,stat,cmd | grep " Z " || true
    fi

    # Show pipes/connections
    local pipe_count
    pipe_count=$(lsof -p "$pid" 2>/dev/null | grep -c pipe || echo 0)
    if (( pipe_count > 0 )); then
        echo "  Open pipes: $pipe_count (possibly stuck waiting on dead MCPs)"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Kill a process
kill_process() {
    local pid=$1
    local dry_run=$2

    if [[ "$dry_run" == "true" ]]; then
        echo "[DRY RUN] Would execute: kill -9 $pid"
    else
        echo "Killing process $pid..."
        kill -9 "$pid"
        echo "✓ Process $pid killed"
    fi
}

# Main execution
main() {
    # Check for help first
    for arg in "$@"; do
        if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
            cat << 'EOF'
Usage: __kill_stuck_claude.sh [OPTIONS]
  -t, --threshold CPU_PERCENT   CPU threshold (default: 80)
  -a, --auto                    Auto-kill without confirmation
  -d, --dry-run                 Show what would be killed
  -h, --help                    Show this help
EOF
            exit 0
        fi
    done

    local args
    args=$(parse_args "$@")
    IFS='|' read -r cpu_threshold auto_kill dry_run <<< "$args"

    echo "Scanning for stuck Claude processes (CPU > ${cpu_threshold}%)..."
    echo ""

    local found_processes=false
    while IFS='|' read -r pid cpu mem time zombies; do
        found_processes=true
        show_process_details "$pid" "$cpu" "$mem" "$time" "$zombies"
        echo ""

        if [[ "$auto_kill" == "true" ]]; then
            kill_process "$pid" "$dry_run"
        else
            read -rp "Kill this process? [y/N] " response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                kill_process "$pid" "$dry_run"
            else
                echo "Skipped process $pid"
            fi
        fi
        echo ""
    done < <(get_stuck_processes "$cpu_threshold")

    if [[ "$found_processes" == "false" ]]; then
        echo "✓ No stuck Claude processes found"
        exit 0
    fi

    # Show updated CPU usage
    if [[ "$dry_run" == "false" ]]; then
        echo ""
        echo "Current system status:"
        top -b -n 1 | head -n 5
    fi
}

main "$@"
