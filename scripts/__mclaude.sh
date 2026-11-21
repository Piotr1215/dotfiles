#!/usr/bin/env bash
set -eo pipefail

# Launch Claude Code against a local model with a bare configuration so the
# normal hooks, MCP servers, instructions, and agent environment do not load.

# Reject flags that would turn off permission prompts before doing any work.
check_permissions() {
  local arg previous=''
  for arg in "$@"; do
    case "$arg" in
      --dangerously-skip-permissions|--allow-dangerously-skip-permissions|--permission-mode=bypassPermissions)
        echo 'mclaude: bypassing permissions is not allowed' >&2
        exit 2
        ;;
    esac
    if [[ "$previous" == --permission-mode && "$arg" == bypassPermissions ]]; then
      echo 'mclaude: bypassing permissions is not allowed' >&2
      exit 2
    fi
    previous="$arg"
  done
}

check_permissions "$@"

llama_dir="${MCLAUDE_LLAMA_DIR:-$HOME/.local/opt/llama.cpp-b12613}"
server="${MCLAUDE_SERVER:-$llama_dir/llama-b12613/llama-server}"
libs="${MCLAUDE_LIBS:-$llama_dir/llama-b12613:$llama_dir/cudart-llama-b12613-bin-ubuntu-cuda-13.5-x64}"
gguf="${MCLAUDE_GGUF:-$HOME/models/inkling-2-mini/Inkling-2-Mini-UD-Q4_K_M.gguf}"
port="${MCLAUDE_PORT:-8090}"
ctx="${MCLAUDE_CTX:-49152}"
idle="${MCLAUDE_IDLE:-600}"
need_mib="${MCLAUDE_NEED_MIB:-10600}"
watch_interval="${MCLAUDE_WATCH_INTERVAL:-30}"
state="${MCLAUDE_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/mclaude}"
config="${MCLAUDE_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/mclaude}"
claude="${MCLAUDE_CLAUDE:-$HOME/.local/bin/claude}"
power_dir="${MCLAUDE_POWER_DIR:-/sys/class/power_supply}"

# Check that a pid exists and is not a zombie waiting for its parent.
process_alive() {
  local pid="$1" state_code
  [[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 1 ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  state_code="$(ps -o stat= -p "$pid" 2>/dev/null)" || return 1
  [[ "$state_code" != *Z* ]]
}

# Read a pid file and reject missing or invalid process IDs.
read_pid() {
  local file="$1" pid
  [[ -r "$file" ]] || return 1
  read -r pid < "$file" || return 1
  [[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 1 ]] || return 1
  printf '%s\n' "$pid"
}

# Stop a recorded process, allowing ten seconds for it to exit.
stop_pid() {
  local file="$1" pid i
  pid="$(read_pid "$file")" || return 0
  if [[ "$pid" != "$$" ]] && process_alive "$pid"; then
    kill "$pid" 2>/dev/null || true
    for ((i = 0; i < 100; i++)); do
      process_alive "$pid" || break
      sleep 0.1
    done
    if process_alive "$pid"; then
      kill -KILL "$pid" 2>/dev/null || true
    fi
  fi
}

# Stop the managed server and watchdog and remove their pid files.
stop_server() {
  stop_pid "$state/watchdog.pid"
  stop_pid "$state/server.pid"
  rm -f "$state/server.pid" "$state/watchdog.pid"
}

# Report the health endpoint and any managed server pid and GPU usage.
show_status() {
  local pid
  if healthy; then printf 'up\n'; else printf 'down\n'; fi
  pid="$(read_pid "$state/server.pid")" || pid='none'
  printf 'server pid: %s\n' "$pid"
  nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader
}

# Check whether the configured endpoint accepts health requests.
healthy() {
  curl -sf --max-time 2 "http://127.0.0.1:$port/health" >/dev/null
}

# Check AC power and available VRAM before starting the local model.
preflight() {
  local ac found=0 online=0 memory total used free
  if [[ "${MCLAUDE_FORCE:-}" != 1 ]]; then
    for ac in "$power_dir"/AC*/online; do
      [[ -f "$ac" ]] || continue
      found=1
      if [[ "$(cat "$ac")" == 1 ]]; then online=1; fi
    done
    if (( found && ! online )); then
      echo 'mclaude: on battery, plug in or MCLAUDE_FORCE=1' >&2
      return 3
    fi
  fi
  if ! memory="$(nvidia-smi --query-gpu=memory.total,memory.used --format=csv,noheader,nounits)"; then
    echo 'mclaude: could not determine free VRAM' >&2
    return 3
  fi
  IFS=, read -r total used <<< "$memory"
  total="${total//[[:space:]]/}"
  used="${used//[[:space:]]/}"
  if [[ ! "$total" =~ ^[0-9]+$ || ! "$used" =~ ^[0-9]+$ ]]; then
    echo 'mclaude: could not determine free VRAM' >&2
    return 3
  fi
  free=$((total - used))
  if (( free < need_mib )); then
    echo "mclaude: insufficient VRAM: ${free} MiB free, ${need_mib} MiB needed" >&2
    nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader >&2 || true
    echo 'mclaude: check for a running game or use classif unload' >&2
    return 3
  fi
}

# Start the server if needed and wait for its health endpoint.
ensure_server() {
  local pid i
  healthy && return 0
  preflight || return $?
  mkdir -p "$state"
  echo 'mclaude: starting local model server' >&2
  LD_LIBRARY_PATH="$libs" setsid nohup "$server" -m "$gguf" --alias inkling-2-mini \
    --host 127.0.0.1 --port "$port" -ngl 99 \
    -ot 'blk\.([0-5]|1[89]|2[0-3])\.ffn_.*_exps\.=CPU' \
    -fa on -c "$ctx" -ub 128 -ctk q8_0 -ctv q8_0 -np 1 --jinja \
    --temp 1.0 --top-p 1.0 --top-k 0 --min-p 0.0 >"$state/server.log" 2>&1 < /dev/null &
  pid=$!
  printf '%s\n' "$pid" > "$state/server.pid"
  for ((i = 0; i < 90; i++)); do
    if healthy; then
      start_watchdog
      return 0
    fi
    if ! process_alive "$pid"; then
      echo 'mclaude: server exited during startup' >&2
      tail -n 20 "$state/server.log" >&2
      rm -f "$state/server.pid"
      return 1
    fi
    sleep 1
  done
  echo 'mclaude: server did not become healthy within 90 seconds' >&2
  tail -n 20 "$state/server.log" >&2
  stop_pid "$state/server.pid"
  rm -f "$state/server.pid"
  return 1
}

# Start one detached watchdog for the managed server.
start_watchdog() {
  local pid
  if pid="$(read_pid "$state/watchdog.pid")" && process_alive "$pid"; then return; fi
  setsid nohup "$0" __watchdog > /dev/null 2>&1 < /dev/null &
  printf '%s\n' "$!" > "$state/watchdog.pid"
}

# Stop an idle server once no live launcher sessions remain.
watchdog() {
  local pid file session_pid active modified now
  while :; do
    sleep "$watch_interval"
    pid="$(read_pid "$state/server.pid")" || break
    process_alive "$pid" || break
    active=0
    for file in "$state"/sessions/*; do
      [[ -f "$file" ]] || continue
      session_pid="${file##*/}"
      if process_alive "$session_pid"; then active=1; else rm -f "$file"; fi
    done
    if (( ! active )) && [[ -f "$state/server.log" ]]; then
      modified="$(stat -c %Y "$state/server.log")"
      now="$(date +%s)"
      if (( now - modified >= idle )); then
        stop_server
        return
      fi
    fi
  done
  rm -f "$state/watchdog.pid"
}

# Remove this launcher's session marker after Claude exits.
cleanup_session() {
  rm -f "$state/sessions/$$"
}

# Launch Claude with only the explicitly allowed environment and settings.
# Claude Code assumes 1M tokens for an unknown model ID, so it is told the
# server's window minus 8K, compacting while a reply still fits.
run_claude() {
  local name result
  local -a clean_env=()
  mkdir -p "$state/sessions" "$config/claude"
  trap cleanup_session EXIT
  printf '%s\n' "$$" > "$state/sessions/$$"
  ensure_server || return $?
  if [[ ! -e "$config/claude/.claude.json" ]]; then
    printf '%s\n' '{"hasCompletedOnboarding": true}' > "$config/claude/.claude.json"
  fi
  for name in HOME PATH TERM COLORTERM LANG LC_ALL USER SHELL DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR; do
    if [[ -v "$name" ]]; then clean_env+=("$name=${!name}"); fi
  done
  clean_env+=("CLAUDE_CONFIG_DIR=$config/claude" "ANTHROPIC_BASE_URL=http://127.0.0.1:$port"
    'ANTHROPIC_AUTH_TOKEN=local' 'ANTHROPIC_MODEL=inkling-2-mini'
    'ANTHROPIC_DEFAULT_HAIKU_MODEL=inkling-2-mini' 'ANTHROPIC_DEFAULT_SONNET_MODEL=inkling-2-mini'
    'ANTHROPIC_DEFAULT_OPUS_MODEL=inkling-2-mini' 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1'
    'DISABLE_AUTOUPDATER=1' 'DISABLE_TELEMETRY=1'
    "CLAUDE_CODE_MAX_CONTEXT_TOKENS=$((ctx - 8192))")
  result=0
  env -i "${clean_env[@]}" "$claude" --settings '{"disableAllHooks":true}' \
    --setting-sources '' --strict-mcp-config --model inkling-2-mini "$@" || result=$?
  return "$result"
}

case "${1:-}" in
  stop) stop_server ;;
  status) show_status ;;
  __watchdog) watchdog ;;
  *) run_claude "$@" ;;
esac
