#!/usr/bin/env bats

# Ctrl+3 on a cockpit "jump:<name>" token runs __tmux_jump.sh. The cockpit names
# rows gordon (pane tagged triage in task) and kendra (tagged intake), and both
# live in the one task session, so these tests pin that each token lands on its
# own agent's window and pane by id, whatever window is active and wherever the
# windows sit, and that pressing the token you are already on steps to the next
# agent in the session.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__tmux_jump.sh"
  SOCKET="tmux-jump-${BATS_TEST_NUMBER}-$$"
  CMDLOG="${BATS_TEST_TMPDIR}/tmux-commands"
  : > "$CMDLOG"
  PLAIN=$(tmux -L "$SOCKET" -f /dev/null new-session -d -s home -x 200 -y 60 -P -F '#{pane_id}')
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

  # A worker session tagged with its own name, plus an active shell split.
  WORKER=$(tmux -L "$SOCKET" new-session -d -s eng-infra-config-DEVOPS-1017 -P -F '#{pane_id}')
  tmux -L "$SOCKET" set -p -t "$WORKER" @agent_name eng-infra-config-DEVOPS-1017
  WORKER_SHELL=$(tmux -L "$SOCKET" split-window -t "$WORKER" -P -F '#{pane_id}')
  tmux -L "$SOCKET" new-session -d -s scratch-1923

  # Two sessions whose agents share a tag, the cockpit's session:window case.
  POKE_A=$(tmux -L "$SOCKET" new-session -d -s poke-a -n agent -P -F '#{pane_id}')
  POKE_B=$(tmux -L "$SOCKET" new-session -d -s poke-b -n agent -P -F '#{pane_id}')
  tmux -L "$SOCKET" set -p -t "$POKE_A" @agent_name poke
  tmux -L "$SOCKET" set -p -t "$POKE_B" @agent_name poke

  # The script calls `tmux` by name and takes no socket, so a wrapper on PATH is
  # the seam. It pins calls to the test server, answers "which pane is the client
  # on" from FAKE_CURRENT_PANE, and logs and swallows switch-client (a headless
  # server has no client). select-window and select-pane run for real.
  # notify-send is stubbed so no popup reaches the desktop.
  BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$BIN"
  cat > "$BIN/tmux" <<EOS
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$CMDLOG"
if [ "\$1" = display-message ] && [ "\$2" = -p ] && [ "\$3" = '#{pane_id}' ]; then
  printf '%s\n' "\$FAKE_CURRENT_PANE"
  exit 0
fi
[ "\$1" = switch-client ] && exit 0
exec $(command -v tmux) -L "$SOCKET" "\$@"
EOS
  printf '#!/usr/bin/env bash\nprintf "notify %%s\\n" "$*" >> %q\n' "$CMDLOG" > "$BIN/notify-send"
  chmod +x "$BIN/tmux" "$BIN/notify-send"
}

teardown() {
  tmux -L "$SOCKET" kill-server 2>/dev/null || true
}

jump_from() { # jump_from CURRENT-PANE TOKEN
  : > "$CMDLOG"
  run env -u TMUX -u TMUX_PANE PATH="$BIN:$PATH" FAKE_CURRENT_PANE="$1" "$SCRIPT" "$2"
}

switched_to() {
  grep -oP '(?<=^switch-client -t ).*' "$CMDLOG" | tail -1
}

landed_on() { # landed_on PANE: the pane is the active pane of its session's current window
  [ "$(switched_to)" = "$1" ] &&
    [ "$(tmux -L "$SOCKET" display-message -p -t "$1" '#{window_active}#{pane_active}')" = 11 ]
}

@test "outside task, jump:gordon lands on gordon although kendra's window is active" {
  jump_from "$PLAIN" jump:gordon
  [ "$status" -eq 0 ]
  landed_on "$GORDON"
  [ "$(tmux -L "$SOCKET" display-message -p -t "$KENDRA" '#{window_active}')" -eq 0 ]
}

@test "the cockpit's gordon token resolves to the pane tagged triage" {
  [ "$(tmux -L "$SOCKET" show-options -pqv -t "$GORDON" @agent_name)" = triage ]
  jump_from "$PLAIN" jump:gordon
  ! grep -q '^notify' "$CMDLOG"
  landed_on "$GORDON"
}

@test "on gordon, jump:gordon steps to kendra" {
  jump_from "$GORDON" jump:gordon
  landed_on "$KENDRA"
}

@test "on kendra, jump:kendra steps back to gordon" {
  jump_from "$KENDRA" jump:kendra
  landed_on "$GORDON"
}

@test "on kendra, jump:gordon lands on gordon" {
  jump_from "$KENDRA" jump:gordon
  landed_on "$GORDON"
}

@test "the cockpit's kendra row lands on kendra, from outside and from gordon" {
  jump_from "$PLAIN" jump:kendra
  landed_on "$KENDRA"
  jump_from "$GORDON" jump:kendra
  landed_on "$KENDRA"
}

@test "from the margin pane in gordon's window, jump:gordon lands on gordon" {
  tmux -L "$SOCKET" select-window -t task:todo
  jump_from "$MARGIN" jump:gordon
  landed_on "$GORDON"
}

@test "windows are found by tag, not index" {
  # Kendra's window moved in front of todo shifts every index.
  tmux -L "$SOCKET" move-window -s task:kendra -t task:9
  tmux -L "$SOCKET" move-window -s task:todo -t task:5
  tmux -L "$SOCKET" move-window -s task:9 -t task:1
  tmux -L "$SOCKET" select-window -t task:kendra
  jump_from "$PLAIN" jump:gordon
  landed_on "$GORDON"
  jump_from "$GORDON" jump:gordon
  landed_on "$KENDRA"
}

@test "a worker's tag lands on its agent pane, not the active shell split" {
  [ "$(tmux -L "$SOCKET" display-message -p -t "$WORKER_SHELL" '#{pane_active}')" -eq 1 ]
  jump_from "$PLAIN" jump:eng-infra-config-DEVOPS-1017
  landed_on "$WORKER"
}

@test "a shared tag resolves by session and window" {
  jump_from "$PLAIN" jump:poke-b:agent
  landed_on "$POKE_B"
  jump_from "$PLAIN" jump:poke-a:agent
  landed_on "$POKE_A"
}

@test "an id inside a session name still reaches its agent" {
  jump_from "$PLAIN" jump:DEVOPS-1017
  landed_on "$WORKER"
}

@test "a session with no tagged agent falls back to the session" {
  jump_from "$PLAIN" jump:1923
  [ "$status" -eq 0 ]
  [ "$(switched_to)" = scratch-1923 ]
  ! grep -q '^select-pane' "$CMDLOG"
}

@test "an unknown name notifies and switches nothing" {
  jump_from "$PLAIN" jump:192
  [ "$status" -eq 0 ]
  ! grep -q '^switch-client' "$CMDLOG"
  grep -q '^notify tmux-jump no live agent for 192' "$CMDLOG"
}

@test "an empty hint does nothing" {
  jump_from "$PLAIN" jump:
  [ "$status" -eq 0 ]
  [ ! -s "$CMDLOG" ]
}
