#!/usr/bin/env bash
set -eo pipefail

export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/go/bin:$PATH"
export EDITOR="${EDITOR:-nvim}"
export VISUAL="${VISUAL:-nvim}"

# Match the Claude launch contract: resolve the current directory's environment
# before freezing the launch-time Kubernetes base or starting the app-server.
if command -v direnv &>/dev/null; then
    eval "$(direnv export bash 2>/dev/null)"
fi

account_lib="$HOME/.claude/scripts/__lib_claude_account.sh"
# shellcheck source=/dev/null
source "$account_lib" 2>/dev/null || claude_work_predicate() { return 1; }

# Cwd is the same account-routing source of truth used by Claude. Route OAuth
# through the matching browser profile as part of the process-local environment.
if [[ -d "$HOME/.codex-work" ]] && claude_work_predicate "$PWD"; then
    export CODEX_HOME="$HOME/.codex-work"
    export BROWSER="google-chrome"
else
    unset CODEX_HOME
    export BROWSER="librewolf"
fi

codex_bin="${CODEX_BIN:-$HOME/.npm-global/bin/codex}"
codex_home="${CODEX_HOME:-$HOME/.codex}"
codex_config_root="${CODEX_CONFIG_ROOT:-$HOME/.codex}"
kctx_bin="${KCTX_BIN:-$HOME/.local/bin/kctx}"
pane_key="global"

# Keep shared configuration and Claude-authored skills current on every
# interactive entry point. MCP synchronization remains explicit because OAuth
# and server probes can block startup.
if [[ -x "$codex_config_root/scripts/__codex_skills_sync.sh" ]]; then
    if [[ "$codex_home" == "$HOME/.codex-work" ]] \
        && [[ -x "$codex_config_root/scripts/__codex_config_overlay.sh" ]]; then
        "$codex_config_root/scripts/__codex_config_overlay.sh" "$codex_config_root" "$codex_home" >/dev/null
    else
        "$codex_config_root/scripts/__codex_skills_sync.sh" "$codex_home" >/dev/null
    fi
fi

bind_pane_kubeconfig() {
    local target_pane="${CODEX_TMUX_PANE:-${TMUX_PANE:-}}"
    [[ -n "${TMUX:-}" && -n "$target_pane" ]] || return 0

    if [[ ! -x "$kctx_bin" ]]; then
        echo "Codex cannot initialize pane Kubernetes state: $kctx_bin is not executable" >&2
        exit 1
    fi

    local base_kubeconfig="${KUBECONFIG:-$HOME/.kube/config}"
    local pane_kubeconfig
    if ! pane_kubeconfig="$($kctx_bin runtime init "$target_pane" --base "$base_kubeconfig")"; then
        echo "Codex cannot initialize pane Kubernetes state for $target_pane" >&2
        exit 1
    fi

    case "$pane_kubeconfig" in
        */selection.yaml:*/view.yaml) ;;
        *)
            echo "Codex received an invalid pane kubeconfig from kctx" >&2
            exit 1
            ;;
    esac

    export KUBECONFIG="$pane_kubeconfig"

    local selection_path="${pane_kubeconfig%%:*}"
    local pane_dir="${selection_path%/selection.yaml}"
    pane_key="${pane_dir##*/}"
    if [[ -z "$pane_key" || "$pane_key" == "$pane_dir" ]]; then
        echo "Codex could not derive the kctx pane key" >&2
        exit 1
    fi
}

# Commands that do not open or control an interactive TUI must keep using the
# binary directly; most reject --remote. Bare `codex` and the interactive
# thread-management commands attach to the managed local app-server instead.
case "${1:-}" in
    exec|e|review)
        bind_pane_kubeconfig
        exec "$codex_bin" "$@"
        ;;
    login|logout|mcp|plugin|mcp-server|app-server|remote-control|completion|update|doctor|sandbox|debug|apply|cloud|exec-server|features|help|-h|--help|-V|--version)
        exec "$codex_bin" "$@"
        ;;
esac

bind_pane_kubeconfig

# Tool subprocesses inherit the app-server environment, not the attaching
# client's environment. A global daemon would therefore collapse all tmux
# panes onto one KUBECONFIG. Keep one control socket per composite kctx pane key
# so every long-lived Codex process remains pinned to its own file pair. Use a
# collision-resistant prefix so the Unix socket remains below Linux's pathname
# limit; the full hash remains authoritative in the kctx runtime path.
control_key="${pane_key:0:16}"
control_dir="$codex_home/app-server-control/$control_key"
socket_path="$control_dir/app-server-control.sock"
export CODEX_APP_SERVER_SOCKET="$socket_path"
pid_file="$control_dir/app-server.pid"
log_file="$codex_home/logs/app-server-$control_key.log"
client_lock="$control_dir/client.lock"

mkdir -p "$control_dir" "$(dirname "$log_file")"
exec 9>"$control_dir/launcher.lock"
flock 9

server_pid=""
started_server=0
if [[ -f "$pid_file" ]]; then
    read -r server_pid < "$pid_file" || server_pid=""
fi

if [[ -z "$server_pid" ]] || ! kill -0 "$server_pid" 2>/dev/null || [[ ! -S "$socket_path" ]]; then
    nohup "$codex_bin" app-server --listen "unix://$socket_path" </dev/null >>"$log_file" 2>&1 &
    server_pid=$!
    started_server=1
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

# Hold a shared client lock while this TUI is attached. The last client to exit
# takes the exclusive lock and owns shutting down the pane-local app-server.
exec 8>"$client_lock"
flock -s 8
flock -u 9
exec 9>&-

set +e
"$codex_bin" --remote "unix://$socket_path" "$@"
client_status=$?
set -e

exec 9>"$control_dir/launcher.lock"
flock 9
flock -u 8
if flock -n -x 8; then
    if [[ "$server_pid" =~ ^[0-9]+$ ]] && kill -0 "$server_pid" 2>/dev/null; then
        kill -TERM "$server_pid" 2>/dev/null || true
        if [[ $started_server -eq 1 ]]; then
            wait "$server_pid" 2>/dev/null || true
        else
            for _ in {1..20}; do
                kill -0 "$server_pid" 2>/dev/null || break
                sleep 0.05
            done
        fi
    fi
    if ! [[ "$server_pid" =~ ^[0-9]+$ ]] || ! kill -0 "$server_pid" 2>/dev/null; then
        rm -f "$socket_path" "$pid_file"
    fi
fi
flock -u 8
exec 8>&-
flock -u 9
exec 9>&-
exit "$client_status"
