#!/usr/bin/env bash
set -eo pipefail

codex_bin="${CODEX_BIN:-$HOME/.npm-global/bin/codex}"
codex_home="${CODEX_HOME:-$HOME/.codex}"
control_dir="$codex_home/app-server-control"
socket_path="$control_dir/app-server-control.sock"
pid_file="$control_dir/app-server.pid"
log_file="$codex_home/logs/app-server.log"

# Commands that do not open or control an interactive TUI must keep using the
# binary directly; most reject --remote. Bare `codex` and the interactive
# thread-management commands attach to the managed local app-server instead.
case "${1:-}" in
    exec|e|review|login|logout|mcp|plugin|mcp-server|app-server|remote-control|completion|update|doctor|sandbox|debug|apply|cloud|exec-server|features|help|-h|--help|-V|--version)
        exec "$codex_bin" "$@"
        ;;
esac

mkdir -p "$control_dir" "$(dirname "$log_file")"
exec 9>"$control_dir/launcher.lock"
flock 9

server_pid=""
if [[ -f "$pid_file" ]]; then
    read -r server_pid < "$pid_file" || server_pid=""
fi

if [[ -z "$server_pid" ]] || ! kill -0 "$server_pid" 2>/dev/null || [[ ! -S "$socket_path" ]]; then
    nohup "$codex_bin" app-server --listen unix:// </dev/null >>"$log_file" 2>&1 &
    server_pid=$!
    printf '%s\n' "$server_pid" > "$pid_file"

    for _ in {1..100}; do
        [[ -S "$socket_path" ]] && break
        if ! kill -0 "$server_pid" 2>/dev/null; then
            echo "Codex app-server failed to start; see $log_file" >&2
            exit 1
        fi
        sleep 0.05
    done
fi

if [[ ! -S "$socket_path" ]]; then
    echo "Codex app-server socket did not appear; see $log_file" >&2
    exit 1
fi

flock -u 9
exec 9>&-
exec "$codex_bin" --remote unix:// "$@"
