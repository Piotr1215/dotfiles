#!/usr/bin/env bats

# M-i walks the panes __cockpit_state.sh lists, in its order. The cockpit is
# stubbed with a script that prints a fixed pane order, so these tests pin the
# cycler's own logic (next, wrap, entry from a non-agent pane, pane landing).
# The order itself is tested against the real renderer in
# ~/.claude/tests/test_cockpit_state_vertical.sh.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__cycle_agent_session.sh"
  SOCKET="cycle-agent-${BATS_TEST_NUMBER}-$$"
  CMDLOG="${BATS_TEST_TMPDIR}/tmux-commands"
  : > "$CMDLOG"
  tmux -L "$SOCKET" -f /dev/null new-session -d -s home -x 120 -y 30

  # Layout mirrors the real shared case: gordon and intake are two windows of
  # the one `task` session, and the other agents live in their own sessions.
  GORDON=$(tmux -L "$SOCKET" new-session -d -s task -P -F '#{pane_id}')
  INTAKE=$(tmux -L "$SOCKET" new-window -d -t task -P -F '#{pane_id}')
  ITIN=$(tmux -L "$SOCKET" new-session -d -s itinerary -P -F '#{pane_id}')
  SLACK=$(tmux -L "$SOCKET" new-session -d -s slackbot -P -F '#{pane_id}')
  HOMELAB=$(tmux -L "$SOCKET" new-session -d -s homelab -P -F '#{pane_id}')
  PLAIN=$(tmux -L "$SOCKET" list-panes -t home -F '#{pane_id}' | head -1)

  # Cockpit order: gordon, its subagents, a later agent, then intake last.
  STATE="${BATS_TEST_TMPDIR}/state"
  printf '#!/usr/bin/env bash\n[ "$COCKPIT_LAYOUT" = order ] || exit 1\nprintf "%%s\\n" %s %s %s %s %s\n' \
    "$GORDON" "$ITIN" "$SLACK" "$HOMELAB" "$INTAKE" > "$STATE"
  chmod +x "$STATE"

  # The script calls `tmux` by name and takes no socket, so a wrapper on PATH is
  # the seam. It pins calls to the test server, answers "which pane am I in" from
  # FAKE_CURRENT_PANE (a headless server has no attached client), and logs and
  # swallows switch-client for the same reason. Which pane the script CHOSE is
  # the logic under test, so the log is the assertion surface. select-window and
  # select-pane still run for real.
  BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$BIN"
  cat > "$BIN/tmux" <<EOS
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$CMDLOG"
if [ "\$1" = display-message ] && [ "\$2" = -p ] && [ "\$3" = '#{pane_id}' ]; then
  printf '%s\n' "\$FAKE_CURRENT_PANE"
  exit 0
fi
if [ "\$1" = switch-client ]; then
  exit 0
fi
exec $(command -v tmux) -L "$SOCKET" "\$@"
EOS
  chmod +x "$BIN/tmux"
}

teardown() {
  tmux -L "$SOCKET" kill-server 2>/dev/null || true
}

cycle_from() {
  run env PATH="$BIN:$PATH" COCKPIT_STATE="$STATE" CYCLE_AGENT_CACHE_DIR="$BATS_TEST_TMPDIR/cache" \
    FAKE_CURRENT_PANE="$1" "$SCRIPT" "${2:-next}" "$1"
}

switched_to() {
  grep -oP '(?<=^switch-client -t ).*' "$CMDLOG" | tail -1
}

@test "next steps through the cockpit order one entry at a time" {
  cycle_from "$GORDON"
  [ "$status" -eq 0 ]
  [ "$(switched_to)" = "$ITIN" ]
  cycle_from "$ITIN"
  [ "$(switched_to)" = "$SLACK" ]
  cycle_from "$HOMELAB"
  [ "$(switched_to)" = "$INTAKE" ]
}

@test "next wraps from the last entry back to the first" {
  cycle_from "$INTAKE"
  [ "$status" -eq 0 ]
  [ "$(switched_to)" = "$GORDON" ]
}

@test "gordon and intake share the task session but are separate stops" {
  cycle_from "$HOMELAB"
  [ "$(switched_to)" = "$INTAKE" ]
  # Intake is selected as its own window inside task, not just the session.
  [ "$(tmux -L "$SOCKET" display-message -p -t "$INTAKE" '#{window_active}')" -eq 1 ]
  [ "$(tmux -L "$SOCKET" display-message -p -t "$GORDON" '#{window_active}')" -eq 0 ]
  cycle_from "$INTAKE"
  [ "$(switched_to)" = "$GORDON" ]
  [ "$(tmux -L "$SOCKET" display-message -p -t "$GORDON" '#{window_active}')" -eq 1 ]
}

@test "a pane that is not an agent enters at the first entry" {
  cycle_from "$PLAIN"
  [ "$(switched_to)" = "$GORDON" ]
}

@test "prev walks backwards, wraps, and enters at the last from outside" {
  cycle_from "$ITIN" prev
  [ "$(switched_to)" = "$GORDON" ]
  cycle_from "$GORDON" prev
  [ "$(switched_to)" = "$INTAKE" ]
  cycle_from "$PLAIN" prev
  [ "$(switched_to)" = "$INTAKE" ]
}

@test "an empty cockpit does nothing" {
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STATE"
  cycle_from "$GORDON"
  [ "$status" -eq 0 ]
  ! grep -q '^switch-client' "$CMDLOG"
}

@test "a bad direction is rejected without switching" {
  cycle_from "$GORDON" --dry
  [ "$status" -eq 2 ]
  ! grep -q '^switch-client' "$CMDLOG"
}

@test "a warm cache is used without rendering the cockpit" {
  cycle_from "$GORDON"
  # Replace the renderer with one that would hang; a press inside the ttl must not run it.
  printf '#!/usr/bin/env bash\nsleep 5\nexit 1\n' > "$STATE"
  start=$(date +%s%N)
  cycle_from "$ITIN"
  elapsed=$(( ($(date +%s%N) - start) / 1000000 ))
  [ "$(switched_to)" = "$SLACK" ]
  [ "$elapsed" -lt 150 ]
}

@test "a stale cache is used now and refreshed in the background" {
  cycle_from "$GORDON"
  touch -d '1 minute ago' "$BATS_TEST_TMPDIR/cache/order"
  printf '#!/usr/bin/env bash\nsleep 1\nprintf "%%s\\n" %s %s\n' "$INTAKE" "$GORDON" > "$STATE"
  start=$(date +%s%N)
  cycle_from "$GORDON"
  elapsed=$(( ($(date +%s%N) - start) / 1000000 ))
  [ "$(switched_to)" = "$ITIN" ]
  [ "$elapsed" -lt 150 ]
  for _ in $(seq 40); do
    [ "$(head -1 "$BATS_TEST_TMPDIR/cache/order")" = "$INTAKE" ] && break
    sleep 0.1
  done
  [ "$(head -1 "$BATS_TEST_TMPDIR/cache/order")" = "$INTAKE" ]
}

@test "a pane that died since the render is skipped" {
  cycle_from "$GORDON"
  tmux -L "$SOCKET" kill-session -t itinerary
  cycle_from "$GORDON"
  [ "$(switched_to)" = "$SLACK" ]
}

@test "the tmux binding drives the cycler with no popup" {
  config="${BATS_TEST_DIRNAME}/../../.tmux.conf"
  grep -qE '^bind -n M-i run-shell .*__cycle_agent_session\.sh next' "$config"
  # A dialog is exactly what this key must not open.
  ! grep -E '^bind -n M-i ' "$config" | grep -q 'display-popup'
  ! grep -qE '^bind -n M-i .*__orchestrator\.sh' "$config"
}

@test "the other session switchers are not bound to this script" {
  config="${BATS_TEST_DIRNAME}/../../.tmux.conf"
  ! grep -E '(M|C)-(PageUp|PageDown)' "$config" | grep -q __cycle_agent_session
}
