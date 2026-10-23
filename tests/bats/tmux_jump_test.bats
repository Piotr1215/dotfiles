#!/usr/bin/env bats

# Ctrl+3 on a cockpit "jump:<id>" token runs __tmux_jump.sh. The cockpit prints
# jump:task for Gordon's row, and task also holds Kendra's window, so these tests
# pin that the jump lands on the agent's pane by id, whatever window is active
# and wherever Kendra's window sits.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__tmux_jump.sh"
  SOCKET="tmux-jump-${BATS_TEST_NUMBER}-$$"
  CMDLOG="${BATS_TEST_TMPDIR}/tmux-commands"
  : > "$CMDLOG"
  tmux -L "$SOCKET" -f /dev/null new-session -d -s home -x 200 -y 60
  tmux -L "$SOCKET" set -g base-index 1

  # task mirrors tmuxinator: todo holds the margin, two tuis and Gordon (tagged
  # triage); Kendra's window (tagged intake) is inserted after it by hand.
  MARGIN=$(tmux -L "$SOCKET" new-session -d -s task -n todo -x 200 -y 60 -P -F '#{pane_id}')
  tmux -L "$SOCKET" split-window -d -t "$MARGIN"
  tmux -L "$SOCKET" split-window -d -h -t "$MARGIN"
  GORDON=$(tmux -L "$SOCKET" split-window -d -t "$MARGIN" -P -F '#{pane_id}')
  tmux -L "$SOCKET" set -p -t "$GORDON" @agent_name triage
  KENDRA=$(tmux -L "$SOCKET" new-window -d -a -t task:todo -n kendra -P -F '#{pane_id}')
  tmux -L "$SOCKET" set -p -t "$KENDRA" @agent_name intake

  # The state that broke the jump: Kendra's window visited last, and inside todo
  # the margin pane active rather than Gordon.
  tmux -L "$SOCKET" select-pane -t "$MARGIN"
  tmux -L "$SOCKET" select-window -t task:kendra

  # A worker session: one tagged agent pane plus an active shell split.
  WORKER=$(tmux -L "$SOCKET" new-session -d -s eng-infra-config-DEVOPS-1017 -P -F '#{pane_id}')
  tmux -L "$SOCKET" set -p -t "$WORKER" @agent_name klod
  WORKER_SHELL=$(tmux -L "$SOCKET" split-window -t "$WORKER" -P -F '#{pane_id}')
  tmux -L "$SOCKET" new-session -d -s scratch-1923

  # The script calls `tmux` by name and takes no socket, so a wrapper on PATH is
  # the seam. It pins calls to the test server and logs and swallows
  # switch-client (a headless server has no client). select-window and
  # select-pane run for real. notify-send is stubbed so no popup reaches the
  # desktop.
  BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$BIN"
  cat > "$BIN/tmux" <<EOS
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$CMDLOG"
[ "\$1" = switch-client ] && exit 0
exec $(command -v tmux) -L "$SOCKET" "\$@"
EOS
  printf '#!/usr/bin/env bash\nprintf "notify %%s\\n" "$*" >> %q\n' "$CMDLOG" > "$BIN/notify-send"
  chmod +x "$BIN/tmux" "$BIN/notify-send"
}

teardown() {
  tmux -L "$SOCKET" kill-server 2>/dev/null || true
}

jump() {
  run env -u TMUX -u TMUX_PANE PATH="$BIN:$PATH" "$SCRIPT" "$1"
}

switched_to() {
  grep -oP '(?<=^switch-client -t ).*' "$CMDLOG" | tail -1
}

flag() { # flag PANE FORMAT
  tmux -L "$SOCKET" display-message -p -t "$1" "$2"
}

@test "jump:task lands on gordon's pane although kendra's window is active" {
  jump jump:task
  [ "$status" -eq 0 ]
  [ "$(switched_to)" = "$GORDON" ]
  [ "$(flag "$GORDON" '#{window_active}')" -eq 1 ]
  [ "$(flag "$GORDON" '#{pane_active}')" -eq 1 ]
  [ "$(flag "$KENDRA" '#{window_active}')" -eq 0 ]
}

@test "gordon is found by tag, not window index" {
  # Kendra's window moved in front of todo shifts every index.
  tmux -L "$SOCKET" move-window -s task:kendra -t task:9
  tmux -L "$SOCKET" move-window -s task:todo -t task:5
  tmux -L "$SOCKET" move-window -s task:9 -t task:1
  tmux -L "$SOCKET" select-window -t task:kendra
  jump jump:task
  [ "$(switched_to)" = "$GORDON" ]
  [ "$(flag "$GORDON" '#{window_active}')" -eq 1 ]
}

@test "a session's only agent pane wins over its active shell split" {
  [ "$(flag "$WORKER_SHELL" '#{pane_active}')" -eq 1 ]
  jump jump:DEVOPS-1017
  [ "$(switched_to)" = "$WORKER" ]
  [ "$(flag "$WORKER" '#{pane_active}')" -eq 1 ]
}

@test "a session with no tagged agent falls back to the session" {
  jump jump:1923
  [ "$status" -eq 0 ]
  [ "$(switched_to)" = scratch-1923 ]
  ! grep -q '^select-pane' "$CMDLOG"
}

@test "the id matches a whole token only" {
  jump jump:192
  [ "$status" -eq 0 ]
  ! grep -q '^switch-client' "$CMDLOG"
  grep -q '^notify tmux-jump no live agent session for 192' "$CMDLOG"
}

@test "an empty hint does nothing" {
  jump jump:
  [ "$status" -eq 0 ]
  [ ! -s "$CMDLOG" ]
}
