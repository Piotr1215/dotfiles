#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__cycle_agent_session.sh"
  SOCKET="cycle-agent-${BATS_TEST_NUMBER}-$$"
  CMDLOG="${BATS_TEST_TMPDIR}/tmux-commands"
  : > "$CMDLOG"
  tmux -L "$SOCKET" -f /dev/null new-session -d -s home -x 120 -y 30

  # The script calls `tmux` by name and takes no socket argument, so a wrapper
  # on PATH is the only seam. It does three jobs:
  #
  #   1. pins every call to the test server
  #   2. answers "what session am I in" from FAKE_CURRENT_SESSION. A headless
  #      test server has no attached client, so the real display-message has no
  #      current session to report.
  #   3. logs and swallows switch-client, for the same reason: with no client
  #      there is nothing to switch and real tmux would fail. Which session the
  #      script CHOSE is the logic under test, so the log is the assertion
  #      surface. select-window and select-pane still run for real, because
  #      those work without a client and their effect is observable.
  BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$BIN"
  cat > "$BIN/tmux" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$CMDLOG"
if [ "\$1" = display-message ] && [ "\$2" = -p ] && [ "\$3" = '#S' ]; then
  printf '%s\n' "\$FAKE_CURRENT_SESSION"
  exit 0
fi
if [ "\$1" = switch-client ]; then
  exit 0
fi
exec $(command -v tmux) -L "$SOCKET" "\$@"
EOF
  chmod +x "$BIN/tmux"
}

teardown() {
  tmux -L "$SOCKET" kill-server 2>/dev/null || true
}

cycle_from() {
  run env PATH="$BIN:$PATH" FAKE_CURRENT_SESSION="$1" "$SCRIPT" "${2:-next}"
}

spawn_agent_session() {
  local name="$1"
  tmux -L "$SOCKET" new-session -d -s "$name"
  tmux -L "$SOCKET" set-option -t "$name" @agent_spawn_level delegated
  tmux -L "$SOCKET" set-option -pt "$name" @agent_name "$name"
}

switched_to() {
  grep -oP '(?<=^switch-client -t ).*' "$CMDLOG" | tail -1
}

@test "a session with no delegated marker is not in the ring" {
  tmux -L "$SOCKET" new-session -d -s plain
  cycle_from home next
  [ "$status" -eq 0 ]
  [ -z "$(switched_to)" ]
}

@test "pressing the key outside the ring enters at the first subagent" {
  spawn_agent_session bravo
  spawn_agent_session alfa
  cycle_from home next
  [ "$status" -eq 0 ]
  [ "$(switched_to)" = alfa ]
}

@test "cycling steps to the next subagent and wraps past the last" {
  spawn_agent_session alfa
  spawn_agent_session bravo
  cycle_from alfa next
  [ "$status" -eq 0 ]
  [ "$(switched_to)" = bravo ]

  cycle_from bravo next
  [ "$status" -eq 0 ]
  [ "$(switched_to)" = alfa ]
}

# The whole point of the split: Alt-PgUp/PgDn walk your own sessions and skip
# delegated workers, this key walks the workers and skips yours. A regular
# session must never be a destination here, however many of them exist.
@test "your own sessions are never entered by this ring" {
  tmux -L "$SOCKET" new-session -d -s work
  tmux -L "$SOCKET" new-session -d -s notes
  spawn_agent_session alfa
  spawn_agent_session bravo
  cycle_from alfa next
  [ "$status" -eq 0 ]
  [ "$(switched_to)" = bravo ]
  cycle_from bravo next
  [ "$status" -eq 0 ]
  [ "$(switched_to)" = alfa ]
  ! grep -qE '^switch-client -t (work|notes|home)$' "$CMDLOG"
}

@test "prev walks the ring backwards and enters at the last from outside" {
  spawn_agent_session alfa
  spawn_agent_session bravo
  cycle_from home prev
  [ "$status" -eq 0 ]
  [ "$(switched_to)" = bravo ]

  cycle_from bravo prev
  [ "$status" -eq 0 ]
  [ "$(switched_to)" = alfa ]
}

@test "a one-session ring does not switch to where you already are" {
  spawn_agent_session alfa
  cycle_from alfa next
  [ "$status" -eq 0 ]
  [ -z "$(switched_to)" ]
}

@test "a lone subagent is still reachable from outside the ring" {
  spawn_agent_session alfa
  cycle_from home next
  [ "$status" -eq 0 ]
  [ "$(switched_to)" = alfa ]
}

# A spawned worker session is a viddy monitor pane plus the agent pane, and
# switch-client restores whichever was last active. Visit a worker, click its
# monitor to read it, cycle away, and every later arrival drops the cursor into
# viddy where you cannot type.
@test "arrival selects the agent pane, not the monitor pane beside it" {
  spawn_agent_session alfa
  monitor=$(tmux -L "$SOCKET" split-window -d -t alfa -P -F '#{pane_id}')
  tmux -L "$SOCKET" select-pane -t "$monitor"
  [ "$(tmux -L "$SOCKET" display-message -p -t "$monitor" '#{pane_active}')" -eq 1 ]

  cycle_from home next
  [ "$status" -eq 0 ]
  agent_pane=$(tmux -L "$SOCKET" list-panes -s -t alfa -F '#{pane_id} #{@agent_name}' | awk 'NF > 1 { print $1; exit }')
  [ "$(tmux -L "$SOCKET" display-message -p -t "$agent_pane" '#{pane_active}')" -eq 1 ]
  [ "$(tmux -L "$SOCKET" display-message -p -t "$monitor" '#{pane_active}')" -eq 0 ]
}

# An "is it next?" test treats every typo as prev. Running this with a --dry
# flag it never had switched a live client into a worker session, silently.
@test "an argument that is not a direction is refused, not read as prev" {
  spawn_agent_session alfa
  spawn_agent_session bravo
  cycle_from home --dry
  [ "$status" -eq 2 ]
  [ -z "$(switched_to)" ]
}

@test "the tmux binding drives the cycler with no popup" {
  config="${BATS_TEST_DIRNAME}/../../.tmux.conf"
  grep -qE '^bind -n M-i run-shell .*__cycle_agent_session\.sh next' "$config"
  # A dialog is exactly what this key must not open.
  ! grep -E '^bind -n M-i ' "$config" | grep -q 'display-popup'
  ! grep -qE '^bind -n M-i .*__orchestrator\.sh' "$config"
}

# The two rings are complements. If __cycle_tmux_session.sh ever stops excluding
# delegated sessions, both keys would walk the workers and this one loses its
# reason to exist, so the split is asserted rather than assumed.
@test "the session cycler still excludes what this cycler includes" {
  grep -q 'delegated' "${BATS_TEST_DIRNAME}/../../scripts/__cycle_tmux_session.sh"
}
