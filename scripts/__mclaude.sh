#!/usr/bin/env bash
set -eo pipefail

# mclaude: a plain terminal chat (aichat) with Inkling 2 Mini, served locally
# by llama.cpp. No agent harness and no preloaded prompt: the model reads only
# what you type, so a reply starts in seconds. Claude Code spent 90 s reading
# its own 15K-token preamble here before the first word.
#
#   mclaude                     chat; .file <path> adds a file, .copy the reply,
#                               .model local:high raises reasoning effort
#   mclaude 'question'          one answer; cat draft | mclaude 'tighten this'
#   mclaude web                 start the server and open its own chat page
#   mclaude status | stop

llama_dir="${MCLAUDE_LLAMA_DIR:-$HOME/.local/opt/llama.cpp-b12613}"
server="${MCLAUDE_SERVER:-$llama_dir/llama-b12613/llama-server}"
libs="${MCLAUDE_LIBS:-$llama_dir/llama-b12613:$llama_dir/cudart-llama-b12613-bin-ubuntu-cuda-13.5-x64}"
gguf="${MCLAUDE_GGUF:-$HOME/models/inkling-2-mini/Inkling-2-Mini-UD-Q4_K_M.gguf}"
port="${MCLAUDE_PORT:-8090}"
ctx="${MCLAUDE_CTX:-49152}"
idle="${MCLAUDE_IDLE:-600}"
need_mib="${MCLAUDE_NEED_MIB:-10600}"
watch_interval="${MCLAUDE_WATCH_INTERVAL:-30}"
# The chat template defaults to high reasoning effort (0.9); most of a reply's
# time was hidden reasoning. Low halved typical replies (7 s against 15 s).
effort="${MCLAUDE_EFFORT:-low}"
state="${MCLAUDE_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/mclaude}"
config="${MCLAUDE_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/mclaude}"
aichat="${MCLAUDE_AICHAT:-$HOME/.cargo/bin/aichat}"
opener="${MCLAUDE_OPEN:-xdg-open}"
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
  printf 'chat page: http://127.0.0.1:%s (mclaude web opens it)\n' "$port"
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
    --chat-template-kwargs "{\"reasoning_effort\":\"$effort\"}" --temp 1.0 --top-p 1.0 --top-k 0 --min-p 0.0 >"$state/server.log" 2>&1 < /dev/null &
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

# Remove this launcher's session marker after the chat exits.
cleanup_session() {
  rm -f "$state/sessions/$$"
}

# Write aichat's config with the local server as its only client. Each model
# entry is Inkling at one reasoning effort, sent per request, so .model
# local:high in the chat raises it without a server restart. It is regenerated
# on every run so the port and window always match this script.
write_chat_config() {
  local level
  {
    printf '# Written by __mclaude.sh on every run.\n'
    printf 'model: local:%s\nstream: true\nclients:\n' "$effort"
    printf '  - type: openai-compatible\n    name: local\n'
    printf '    api_base: http://127.0.0.1:%s/v1\n    api_key: local\n    models:\n' "$port"
    for level in none minimal low medium high xhigh; do
      printf '      - name: %s\n        real_name: inkling-2-mini\n' "$level"
      printf '        max_input_tokens: %s\n        max_output_tokens: 8192\n' "$((ctx - 8192))"
      printf '        patch:\n          body:\n            chat_template_kwargs:\n'
      printf '              reasoning_effort: %s\n' "$level"
    done
  } > "$config/aichat/config.yaml"
}

# Run aichat with only the explicitly allowed environment, so a command run
# from its shell mode never sees the caller's tokens or agents-bus identity.
run_chat() {
  local name result=0
  local -a clean_env=()
  if [[ ! -x "$aichat" ]]; then
    echo "mclaude: $aichat not found, install it with: cargo install --locked aichat" >&2
    return 1
  fi
  mkdir -p "$state/sessions" "$config/aichat"
  trap cleanup_session EXIT
  printf '%s\n' "$$" > "$state/sessions/$$"
  ensure_server || return $?
  write_chat_config
  for name in HOME PATH TERM COLORTERM LANG LC_ALL USER SHELL EDITOR VISUAL DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR; do
    if [[ -v "$name" ]]; then clean_env+=("$name=${!name}"); fi
  done
  clean_env+=("AICHAT_CONFIG_DIR=$config/aichat")
  if [[ -t 1 ]]; then
    env -i "${clean_env[@]}" "$aichat" "$@" || result=$?
  else
    env -i "${clean_env[@]}" "$aichat" "$@" | strip_thinking || result=$?
  fi
  return "$result"
}

# Drop the leading <think> block aichat prints for the model's reasoning, so a
# reply piped to the clipboard or a file is the answer alone.
strip_thinking() {
  perl -0777 -pe 's/\A\s*<think>.*?<\/think>\s*//s'
}

# Start the server if needed and open llama-server's chat page, which sends
# only what is typed and starts replying in seconds.
open_web() {
  ensure_server || return $?
  printf 'chat page: http://127.0.0.1:%s\n' "$port"
  "$opener" "http://127.0.0.1:$port" > /dev/null 2>&1 &
}

case "${1:-}" in
  stop) stop_server ;;
  status) show_status ;;
  web) open_web ;;
  __watchdog) watchdog ;;
  *) run_chat "$@" ;;
esac
