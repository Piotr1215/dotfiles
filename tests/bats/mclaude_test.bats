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
  export MCLAUDE_CLAUDE="$BATS_TEST_TMPDIR/bin/claude-stub"
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
  cat > "$MCLAUDE_CLAUDE" <<'STUB'
#!/usr/bin/env bash
printf '%s\0' "$@" > "$HOME/claude-argv"
env > "$HOME/claude-env"
if [[ -f "$HOME/exit-code" ]]; then exit "$(cat "$HOME/exit-code")"; fi
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

# Bypassing permission prompts must be rejected before touching state.
@test "rejects dangerous permission bypass" {
  run "$SCRIPT" --dangerously-skip-permissions
  [ "$status" -eq 2 ]
  [ ! -e "$HOME/claude-argv" ]
  [ ! -e "$MCLAUDE_STATE" ]
  run "$SCRIPT" --allow-dangerously-skip-permissions
  [ "$status" -eq 2 ]
}

# Both forms of permission mode must keep permission prompts enabled.
@test "rejects both bypass permission mode forms" {
  run "$SCRIPT" --permission-mode bypassPermissions
  [ "$status" -eq 2 ]
  run "$SCRIPT" --permission-mode=bypassPermissions
  [ "$status" -eq 2 ]
}

# A server start on battery requires an explicit power override.
@test "refuses battery power unless forced" {
  echo 0 > "$MCLAUDE_POWER_DIR/AC0/online"
  run "$SCRIPT" -p hi
  [ "$status" -eq 3 ]
  [[ "$output" == *'on battery'* ]]
  [ ! -e "$HOME/claude-argv" ]
  export MCLAUDE_FORCE=1
  run "$SCRIPT" -p hi
  [ "$status" -eq 0 ]
  [ -e "$HOME/claude-argv" ]
  [ -e "$HOME/server-argv" ]
}

# VRAM refusal explains the available capacity and competing processes.
@test "refuses insufficient VRAM" {
  echo '12000, 2000' > "$HOME/gpu"
  run "$SCRIPT"
  [ "$status" -eq 3 ]
  [[ "$output" == *'VRAM'*'10000 MiB free'*'10600 MiB needed'* ]]
  [[ "$output" == *'game'* ]]
  [ ! -e "$HOME/claude-argv" ]
}

# A healthy server launches Claude with isolated settings and environment.
@test "passes bare settings and strips caller environment" {
  touch "$HOME/healthy"
  export TMUX_PANE='%42' ANTHROPIC_API_KEY=secret CLAUDE_PANE_ID=secret TMUX=secret
  run "$SCRIPT" -p hi
  [ "$status" -eq 0 ]
  python3 - "$HOME/claude-argv" <<'PY'
import sys
args = open(sys.argv[1], 'rb').read().decode().split('\0')[:-1]
assert args == ['--settings', '{"disableAllHooks":true}', '--setting-sources', '', '--strict-mcp-config', '--model', 'inkling-2-mini', '-p', 'hi'], args
PY
  grep -Fx 'ANTHROPIC_BASE_URL=http://127.0.0.1:18090' "$HOME/claude-env"
  ! grep -E '^(TMUX|TMUX_PANE|CLAUDE_PANE_ID|ANTHROPIC_API_KEY)=' "$HOME/claude-env"
}

# Claude Code assumes 1M tokens for an unknown model ID and would never compact
# before the server's window fills; it must compact with room left for a reply.
@test "tells Claude the server window minus reply room" {
  touch "$HOME/healthy"
  run "$SCRIPT" -p hi
  [ "$status" -eq 0 ]
  grep -Fx 'CLAUDE_CODE_MAX_CONTEXT_TOKENS=40960' "$HOME/claude-env"
  MCLAUDE_CTX=32768 run "$SCRIPT" -p hi
  [ "$status" -eq 0 ]
  grep -Fx 'CLAUDE_CODE_MAX_CONTEXT_TOKENS=24576' "$HOME/claude-env"
}

# Child failures must reach the caller without leaving a live session marker.
@test "propagates Claude exit code and removes session" {
  touch "$HOME/healthy"
  echo 17 > "$HOME/exit-code"
  run "$SCRIPT"
  [ "$status" -eq 17 ]
  [ -z "$(find "$MCLAUDE_STATE/sessions" -type f -print -quit)" ]
}

# A separate config must skip onboarding without changing an existing config.
@test "writes onboarding state only when missing" {
  touch "$HOME/healthy"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  python3 - "$MCLAUDE_CONFIG/claude/.claude.json" <<'PY'
import json, sys
assert json.load(open(sys.argv[1])) == {'hasCompletedOnboarding': True}
PY
  echo '{"existing": true}' > "$MCLAUDE_CONFIG/claude/.claude.json"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -Fx '{"existing": true}' "$MCLAUDE_CONFIG/claude/.claude.json"
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
  run "$SCRIPT" -p hi
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

# Startup failure must report the log and never call Claude.
@test "reports an early server exit" {
  cat > "$MCLAUDE_SERVER" <<'STUB'
#!/usr/bin/env bash
echo 'stub server failed'
exit 1
STUB
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *'stub server failed'* ]]
  [ ! -e "$HOME/claude-argv" ]
}

# Status reports the health, server pid, and current GPU use.
@test "status reports health and GPU usage" {
  touch "$HOME/healthy"
  run "$SCRIPT" status
  [ "$status" -eq 0 ]
  [[ "$output" == *up*'server pid: none'*'1000 MiB, 12000 MiB'* ]]
}

# Force bypasses only the battery check, never the GPU capacity check.
@test "force still refuses insufficient VRAM" {
  echo 0 > "$MCLAUDE_POWER_DIR/AC0/online"
  echo '12000, 2000' > "$HOME/gpu"
  export MCLAUDE_FORCE=1
  run "$SCRIPT"
  [ "$status" -eq 3 ]
  [[ "$output" == *'VRAM'* ]]
  [ ! -e "$HOME/claude-argv" ]
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
