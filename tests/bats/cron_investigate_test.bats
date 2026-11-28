#!/usr/bin/env bats
# Tests for scripts/__cron_investigate.sh, the argos cron row click: it must
# show the cron-manager session in the current Alacritty window (the tmux client
# with the latest input), opening a window only when no client exists.
#
# A real tmux server on a private socket with headless clients (script(1) on a
# fifo), so switch-client and client activity behave as they do live. The
# server starts with -f /dev/null: the user config's session-created hooks
# would add margin panes and music to the test session.

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/__cron_investigate.sh"

setup() {
  T=$(mktemp -d)
  BIN="$T/bin" SPY="$T/spy"
  mkdir -p "$BIN" "$SPY"
  REAL_TMUX=$(command -v tmux)
  SOCK="cron-investigate-$$-$BATS_TEST_NUMBER"
  export REAL_TMUX SOCK SPY
  export SHELL=/bin/sh CRON_INVESTIGATE_BOOT_WAIT=0
  unset TMUX TMUX_PANE

  cat > "$BIN/tmux" <<'EOF'
#!/usr/bin/env bash
exec "$REAL_TMUX" -L "$SOCK" "$@"
EOF
  # The cron-manager layout: a viddy pane, then the agent pane, here a cat that
  # writes what it is typed. Returns once both commands run, as a real start
  # leaves them running.
  cat > "$BIN/tmuxinator" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SPY/tmuxinator.log"
[ "$*" = "start cron-manager --no-attach" ] || exit 2
tmux new-session -d -s cron-manager -n status -x 120 -y 40 "exec viddy 600"
tmux split-window -t cron-manager:status "exec cat >> '$SPY/agent_input'"
for _ in $(seq 100); do
  [ "$(tmux list-panes -t cron-manager:status -F '#{pane_current_command}' | sort | tr '\n' ' ')" = "cat viddy " ] && exit 0
  sleep 0.05
done
exit 1
EOF
  # search --pid answers with the window mapped to that pid in $SPY/windows.
  cat > "$BIN/xdotool" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SPY/xdotool.log"
[ "$1" = search ] && awk -v p="${*: -1}" '$1 == p { print $2 }' "$SPY/windows" 2>/dev/null
exit 0
EOF
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$SPY/alacritty.log"\n' > "$BIN/alacritty"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$SPY/notify.log"\n' > "$BIN/notify-send"
  ln -s "$(command -v sleep)" "$BIN/viddy"
  chmod +x "$BIN"/tmux "$BIN"/tmuxinator "$BIN"/xdotool "$BIN"/alacritty "$BIN"/notify-send
  export PATH="$BIN:$PATH"

  "$REAL_TMUX" -L "$SOCK" -f /dev/null new-session -d -s main -x 80 -y 24 "exec cat"
  "$REAL_TMUX" -L "$SOCK" new-session -d -s other -x 80 -y 24 "exec cat"
  terms=()
}

teardown() {
  "$REAL_TMUX" -L "$SOCK" kill-server 2>/dev/null || true
  local pid
  for pid in "${terms[@]}"; do kill "$pid" 2>/dev/null || true; done
  rm -rf "$T"
}

# Attach a headless client to session $1, as if in an Alacritty window with id
# $2. The script(1) process stands in for the terminal: its pid maps to the
# window, and the client is its descendant, as alacritty -> shell -> tmux.
# The fifo stays open on fd $3 so the test can type into the client later.
attach_client() {
  local session="$1" win="$2" fd_var="$3" fifo="$T/in.$2" fd count
  count=$("$REAL_TMUX" -L "$SOCK" list-clients 2>/dev/null | wc -l)
  mkfifo "$fifo"
  exec {fd}<>"$fifo"
  printf -v "$fd_var" '%s' "$fd"
  TERM=xterm script -q -c "tmux attach-session -t =$session" /dev/null <&"$fd" >/dev/null 2>&1 3>&- &
  terms+=("$!")
  printf '%s %s\n' "$!" "$win" >> "$SPY/windows"
  for _ in $(seq 100); do
    (( $("$REAL_TMUX" -L "$SOCK" list-clients 2>/dev/null | wc -l) > count )) && return 0
    sleep 0.02
  done
  return 1
}

attached_sessions() {
  "$REAL_TMUX" -L "$SOCK" list-clients -F '#{client_session}' | sort | tr '\n' ' '
}

wait_for_file() {
  for _ in $(seq 100); do [ -s "$1" ] && return 0; sleep 0.02; done
  return 1
}

@test "no session: it starts detached and opens in the current window with the job typed" {
  attach_client main 4242 fd_a

  run "$SCRIPT" backup

  [ "$status" -eq 0 ]
  [ "$(cat "$SPY/tmuxinator.log")" = "start cron-manager --no-attach" ]
  [ "$(attached_sessions)" = "cron-manager " ]
  grep -qx 'windowactivate 4242' "$SPY/xdotool.log"
  [ ! -e "$SPY/alacritty.log" ]
  wait_for_file "$SPY/agent_input"
  grep -Fq "/ops-cron-manager show me the status of cron job 'backup'" "$SPY/agent_input"
}

@test "a running session is not started again and the current window switches to it" {
  "$BIN/tmuxinator" start cron-manager --no-attach
  rm "$SPY/tmuxinator.log"
  attach_client main 4242 fd_a

  run "$SCRIPT" backup

  [ "$status" -eq 0 ]
  [ ! -e "$SPY/tmuxinator.log" ]
  [ "$(attached_sessions)" = "cron-manager " ]
  grep -qx 'windowactivate 4242' "$SPY/xdotool.log"
  wait_for_file "$SPY/agent_input"
  grep -Fq "cron job 'backup'" "$SPY/agent_input"
}

@test "the window with the latest input is switched, not the newest attach" {
  attach_client main 4242 fd_a
  attach_client other 4343 fd_b
  # client_activity counts in seconds: type into the older client a second later.
  sleep 1.1
  printf 'x' >&"$fd_a"
  sleep 0.2

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(attached_sessions)" = "cron-manager other " ]
  grep -qx 'windowactivate 4242' "$SPY/xdotool.log"
  ! grep -q 'windowactivate 4343' "$SPY/xdotool.log"
  # No job, no directive: the agent starts on its own full sweep.
  [ ! -s "$SPY/agent_input" ]
}

@test "with no tmux client anywhere a new window attaches the session" {
  run "$SCRIPT"

  [ "$status" -eq 0 ]
  wait_for_file "$SPY/alacritty.log"
  [ "$(cat "$SPY/alacritty.log")" = "-e tmux attach-session -t cron-manager" ]
  [ ! -e "$SPY/xdotool.log" ] || ! grep -q windowactivate "$SPY/xdotool.log"
}

@test "a session that fails to start says so and switches nothing" {
  printf '#!/usr/bin/env bash\nexit 1\n' > "$BIN/tmuxinator"
  attach_client main 4242 fd_a

  run "$SCRIPT" backup

  [ "$status" -eq 1 ]
  grep -Fq 'did not start' "$SPY/notify.log"
  [ "$(attached_sessions)" = "main " ]
}
