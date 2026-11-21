#!/usr/bin/env bats

# Use only temporary stubs and state so tests never touch the real server.
setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__mclaude.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/power/AC0"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export MCLAUDE_STATE="$BATS_TEST_TMPDIR/state"
  export MCLAUDE_CONFIG="$BATS_TEST_TMPDIR/config"
  export MCLAUDE_POWER_DIR="$BATS_TEST_TMPDIR/power"
  export MCLAUDE_AICHAT="$BATS_TEST_TMPDIR/bin/aichat-stub"
  export MCLAUDE_OPEN="$BATS_TEST_TMPDIR/bin/open-stub"
  export MCLAUDE_SERVER="$BATS_TEST_TMPDIR/bin/server-stub"
  export MCLAUDE_PORT=18090 MCLAUDE_NEED_MIB=10600 MCLAUDE_WATCH_INTERVAL=0.1
  echo 1 > "$MCLAUDE_POWER_DIR/AC0/online"
  echo '12000, 1000' > "$HOME/gpu"
  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'STUB'
#!/usr/bin/env bash
[[ -f "$HOME/healthy" ]]
STUB
  cat > "$BATS_TEST_TMPDIR/bin/nvidia-smi" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  --query-compute-apps=*) echo '123, game, 5000 MiB' ;;
  --query-gpu=memory.used,memory.total) echo '1000 MiB, 12000 MiB' ;;
  *) cat "$HOME/gpu" ;;
esac
STUB
  cat > "$MCLAUDE_SERVER" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$HOME/server-argv"
printf '%s\n' "$LD_LIBRARY_PATH" > "$HOME/server-libs"
touch "$HOME/healthy"
exec sleep 300
STUB
  cat > "$MCLAUDE_AICHAT" <<'STUB'
#!/usr/bin/env bash
printf '%s\0' "$@" > "$HOME/aichat-argv"
env > "$HOME/aichat-env"
if [[ -f "$HOME/exit-code" ]]; then exit "$(cat "$HOME/exit-code")"; fi
STUB
  cat > "$MCLAUDE_OPEN" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$HOME/opened"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/"*
}

# Reap only processes created by this test and leave no detached stubs behind.
teardown() {
  local pid
  for file in "$MCLAUDE_STATE/watchdog.pid" "$MCLAUDE_STATE/server.pid" "$HOME/test-watchdog.pid" "$HOME/test-server.pid"; do
    if [[ -f "$file" ]]; then
      read -r pid < "$file" || true
      if [[ "${pid:-}" =~ ^[0-9]+$ ]]; then kill "$pid" 2>/dev/null || true; fi
    fi
  done
  wait 2>/dev/null || true
}

# A server start on battery requires an explicit power override.
@test "refuses battery power unless forced" {
  echo 0 > "$MCLAUDE_POWER_DIR/AC0/online"
  run "$SCRIPT" hi
  [ "$status" -eq 3 ]
  [[ "$output" == *'on battery'* ]]
  [ ! -e "$HOME/aichat-argv" ]
  export MCLAUDE_FORCE=1
  run "$SCRIPT" hi
  [ "$status" -eq 0 ]
  [ -e "$HOME/aichat-argv" ]
  [ -e "$HOME/server-argv" ]
}

# VRAM refusal explains the available capacity and competing processes.
@test "refuses insufficient VRAM" {
  echo '12000, 2000' > "$HOME/gpu"
  run "$SCRIPT"
  [ "$status" -eq 3 ]
  [[ "$output" == *'VRAM'*'10000 MiB free'*'10600 MiB needed'* ]]
  [[ "$output" == *'game'* ]]
  [ ! -e "$HOME/aichat-argv" ]
}

# aichat gets its own config dir, the user's args untouched, and an
# environment without the caller's tokens or agents-bus identity.
@test "runs aichat on its own config with a clean environment" {
  touch "$HOME/healthy"
  export TMUX_PANE='%42' ANTHROPIC_API_KEY=secret GITHUB_TOKEN=secret TMUX=secret EDITOR=nvim
  run "$SCRIPT" hi
  [ "$status" -eq 0 ]
  python3 - "$HOME/aichat-argv" <<'PYX'
import sys
args = open(sys.argv[1], 'rb').read().decode().split('\0')[:-1]
assert args == ['hi'], args
PYX
  grep -Fx "AICHAT_CONFIG_DIR=$MCLAUDE_CONFIG/aichat" "$HOME/aichat-env"
  grep -Fx 'EDITOR=nvim' "$HOME/aichat-env"
  ! grep -E '^(TMUX|TMUX_PANE|ANTHROPIC_API_KEY|GITHUB_TOKEN)=' "$HOME/aichat-env"
}

# The only client is the local server, on the port and window this script
# starts it with, regenerated so a changed port never leaves a stale config.
@test "points aichat at the local server" {
  touch "$HOME/healthy"
  run "$SCRIPT" hi
  [ "$status" -eq 0 ]
  local file="$MCLAUDE_CONFIG/aichat/config.yaml"
  grep -Fx 'model: local:inkling-2-mini' "$file"
  grep -Fx '    api_base: http://127.0.0.1:18090/v1' "$file"
  grep -Fx '        max_input_tokens: 40960' "$file"
  MCLAUDE_PORT=18091 run "$SCRIPT" hi
  grep -Fx '    api_base: http://127.0.0.1:18091/v1' "$file"
}

# Inkling reasons before it answers and aichat prints that as a <think> block;
# a reply piped to the clipboard or a file must be the answer alone.
@test "strips the reasoning block from piped output" {
  touch "$HOME/healthy"
  cat > "$MCLAUDE_AICHAT" <<'STUB'
#!/usr/bin/env bash
printf '<think>\nplan the rewrite\n</think>\n\nHi team, the deploy is late.\n'
STUB
  run "$SCRIPT" 'rewrite this'
  [ "$status" -eq 0 ]
  [ "$output" = 'Hi team, the deploy is late.' ]
}

# Chat failures must reach the caller without leaving a live session marker.
@test "propagates aichat exit code and removes session" {
  touch "$HOME/healthy"
  echo 17 > "$HOME/exit-code"
  run "$SCRIPT"
  [ "$status" -eq 17 ]
  [ -z "$(find "$MCLAUDE_STATE/sessions" -type f -print -quit)" ]
}

# A missing chat client must say how to install it before the GPU is touched.
@test "names the install command when aichat is missing" {
  export MCLAUDE_AICHAT="$BATS_TEST_TMPDIR/bin/no-such-aichat"
  run "$SCRIPT" hi
  [ "$status" -eq 1 ]
  [[ "$output" == *'cargo install --locked aichat'* ]]
  [ ! -e "$HOME/server-argv" ]
}

# The chat page needs the server but not the terminal client.
@test "web starts the server and opens the chat page" {
  run "$SCRIPT" web
  [ "$status" -eq 0 ]
  [[ "$output" == *'chat page: http://127.0.0.1:18090'* ]]
  for _ in $(seq 20); do [ -e "$HOME/opened" ] && break; sleep 0.1; done
  grep -Fx 'http://127.0.0.1:18090' "$HOME/opened"
  [ -e "$HOME/server-argv" ]
  [ ! -e "$HOME/aichat-argv" ]
}

# An idle unmanaged session must not keep the GPU server alive indefinitely.
@test "watchdog stops an idle server and prunes dead sessions" {
  mkdir -p "$MCLAUDE_STATE/sessions"
  sleep 300 &
  local server_pid=$!
  echo "$server_pid" > "$MCLAUDE_STATE/server.pid"
  echo "$server_pid" > "$HOME/test-server.pid"
  touch -d '2 minutes ago' "$MCLAUDE_STATE/server.log"
  touch "$MCLAUDE_STATE/sessions/99999999"
  export MCLAUDE_IDLE=1
  run timeout 5 "$SCRIPT" __watchdog
  [ "$status" -eq 0 ]
  ! kill -0 "$server_pid" 2>/dev/null
  [ ! -e "$MCLAUDE_STATE/server.pid" ]
  [ ! -e "$MCLAUDE_STATE/sessions/99999999" ]
}

# A live launcher session protects the server even if its log looks idle.
@test "watchdog keeps server alive while a session exists" {
  mkdir -p "$MCLAUDE_STATE/sessions"
  sleep 300 &
  local server_pid=$!
  echo "$server_pid" > "$MCLAUDE_STATE/server.pid"
  echo "$server_pid" > "$HOME/test-server.pid"
  touch -d '2 minutes ago' "$MCLAUDE_STATE/server.log"
  touch "$MCLAUDE_STATE/sessions/$$"
  export MCLAUDE_IDLE=1
  "$SCRIPT" __watchdog > /dev/null 2>&1 &
  local watchdog_pid=$!
  echo "$watchdog_pid" > "$HOME/test-watchdog.pid"
  sleep 0.5
  kill -0 "$watchdog_pid"
  kill -0 "$server_pid"
}

# The real startup path must pass the requested model flags and server libraries.
@test "starts detached server with requested flags and library path" {
  export MCLAUDE_LIBS='/test/lib:/test/cuda' MCLAUDE_CTX=12345
  run "$SCRIPT" hi
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/server-libs")" = '/test/lib:/test/cuda' ]
  python3 - "$HOME/server-argv" <<'PY'
import sys
args = open(sys.argv[1]).read().splitlines()
assert args[0] == '-m' and args[1].endswith('/Inkling-2-Mini-UD-Q4_K_M.gguf')
assert args[2:] == ['--alias', 'inkling-2-mini', '--host', '127.0.0.1', '--port', '18090', '-ngl', '99', '-ot', r'blk\.([0-5]|1[89]|2[0-3])\.ffn_.*_exps\.=CPU', '-fa', 'on', '-c', '12345', '-ub', '128', '-ctk', 'q8_0', '-ctv', 'q8_0', '-np', '1', '--jinja', '--temp', '1.0', '--top-p', '1.0', '--top-k', '0', '--min-p', '0.0'], args
PY
  [ -s "$MCLAUDE_STATE/watchdog.pid" ]
}

# Startup failure must report the log and never start the chat.
@test "reports an early server exit" {
  cat > "$MCLAUDE_SERVER" <<'STUB'
#!/usr/bin/env bash
echo 'stub server failed'
exit 1
STUB
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *'stub server failed'* ]]
  [ ! -e "$HOME/aichat-argv" ]
}

# Status reports the health, server pid, and current GPU use.
@test "status reports health and GPU usage" {
  touch "$HOME/healthy"
  run "$SCRIPT" status
  [ "$status" -eq 0 ]
  [[ "$output" == *up*'server pid: none'*'chat page: http://127.0.0.1:18090'*'1000 MiB, 12000 MiB'* ]]
}

# Force bypasses only the battery check, never the GPU capacity check.
@test "force still refuses insufficient VRAM" {
  echo 0 > "$MCLAUDE_POWER_DIR/AC0/online"
  echo '12000, 2000' > "$HOME/gpu"
  export MCLAUDE_FORCE=1
  run "$SCRIPT"
  [ "$status" -eq 3 ]
  [[ "$output" == *'VRAM'* ]]
  [ ! -e "$HOME/aichat-argv" ]
}

# Stop ends both managed processes and removes their pid files.
@test "stop terminates the server and watchdog" {
  mkdir -p "$MCLAUDE_STATE"
  sleep 300 &
  local server_pid=$!
  echo "$server_pid" > "$MCLAUDE_STATE/server.pid"
  echo "$server_pid" > "$HOME/test-server.pid"
  sleep 300 &
  local watchdog_pid=$!
  echo "$watchdog_pid" > "$MCLAUDE_STATE/watchdog.pid"
  echo "$watchdog_pid" > "$HOME/test-watchdog.pid"
  run timeout 5 "$SCRIPT" stop
  [ "$status" -eq 0 ]
  ! kill -0 "$server_pid" 2>/dev/null
  ! kill -0 "$watchdog_pid" 2>/dev/null
  [ ! -e "$MCLAUDE_STATE/server.pid" ]
  [ ! -e "$MCLAUDE_STATE/watchdog.pid" ]
}
