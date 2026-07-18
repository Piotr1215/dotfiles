#!/usr/bin/env bash
set -euo pipefail

dry_run=0
if [[ "${1:-}" == "--dry-run" ]]; then
    dry_run=1
    shift
fi
if [[ $# -ne 0 ]]; then
    echo "usage: $0 [--dry-run]" >&2
    exit 2
fi

kctx_bin="${KCTX_BIN:-$HOME/.local/bin/kctx}"
control_root="${CODEX_CONTROL_ROOT:-$HOME/.codex/app-server-control}"
if [[ -n "${KCTX_RUNTIME_ROOT:-}" ]]; then
    runtime_root="$KCTX_RUNTIME_ROOT"
elif [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    runtime_root="$XDG_RUNTIME_DIR/kctx"
elif [[ -d "/run/user/$(id -u)" ]]; then
    runtime_root="/run/user/$(id -u)/kctx"
else
    runtime_root="${TMPDIR:-/tmp}/kctx-$(id -u)/kctx"
fi

if [[ $dry_run -eq 0 && -x "$kctx_bin" ]]; then
    "$kctx_bin" gc --max-age-seconds 0 >/dev/null
fi

[[ -d "$control_root" ]] || exit 0

for control_dir in "$control_root"/*; do
    [[ -d "$control_dir" ]] || continue
    control_key="${control_dir##*/}"
    [[ "$control_key" =~ ^[0-9a-f]{16}$ ]] || continue

    if [[ -d "$runtime_root" ]] && find "$runtime_root" -mindepth 1 -maxdepth 1 -type d -name "${control_key}*" -print -quit | grep -q .; then
        continue
    fi

    pid_file="$control_dir/app-server.pid"
    socket_path="$control_dir/app-server-control.sock"
    server_pid=""
    if [[ -r "$pid_file" ]]; then
        read -r server_pid < "$pid_file" || true
    fi

    if [[ "$server_pid" =~ ^[0-9]+$ ]] && kill -0 "$server_pid" 2>/dev/null; then
        cmdline="$(tr '\0' ' ' < "/proc/$server_pid/cmdline" 2>/dev/null || true)"
        if [[ "$cmdline" != *"app-server"* || "$cmdline" != *"unix://$socket_path"* ]]; then
            echo "refusing to stop pid $server_pid for unexpected app-server command" >&2
            continue
        fi
        if [[ $dry_run -eq 1 ]]; then
            echo "would stop pane app-server $server_pid ($control_key)"
            continue
        fi
        kill -TERM "$server_pid" 2>/dev/null || true
        for _ in {1..20}; do
            kill -0 "$server_pid" 2>/dev/null || break
            sleep 0.05
        done
        if kill -0 "$server_pid" 2>/dev/null; then
            echo "pane app-server $server_pid did not stop; leaving $control_dir" >&2
            continue
        fi
    elif [[ $dry_run -eq 1 ]]; then
        echo "would remove stale pane app-server state ($control_key)"
        continue
    fi

    rm -rf -- "$control_dir"
done
