#!/usr/bin/env bats

# The renderer supplies cockpit order. A tmux stub models live pane and session
# options so the tests cannot switch a real client or close a real session.
setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__cycle_agent_session.sh"
  CMDLOG="${BATS_TEST_TMPDIR}/tmux-commands"
  LIVE="${BATS_TEST_TMPDIR}/live"
  STATE="${BATS_TEST_TMPDIR}/state"
  BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$BIN"
  : > "$CMDLOG"
  cat > "$LIVE" <<'PANES'
%1|triage|
%2|worker-a|delegated
%3|worker-b|delegated
%4|homelab|
%5|intake|
%6|worker-c|delegated
%7||
PANES
  cat > "$STATE" <<'STATE_SCRIPT'
#!/usr/bin/env bash
[ "$COCKPIT_LAYOUT" = order ] || exit 1
printf '%s\n' %1 %2 %3 %4 %5 %6 %7
STATE_SCRIPT
  chmod +x "$STATE"
  cat > "$BIN/tmux" <<'TMUX_SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CMDLOG"
case "$1" in
  list-panes) cat "$LIVE" ;;
  display-message) printf '%s\n' "$FAKE_CURRENT_PANE" ;;
  switch-client|select-window|select-pane) exit 0 ;;
  *) exit 1 ;;
esac
TMUX_SCRIPT
  chmod +x "$BIN/tmux"
  export CMDLOG LIVE
}

cycle_from() {
  run env PATH="$BIN:$PATH" COCKPIT_STATE="$STATE" CYCLE_AGENT_CACHE_DIR="$BATS_TEST_TMPDIR/cache" \
    FAKE_CURRENT_PANE="$1" "$SCRIPT" "${2:-next}" "$1"
}

switched_to() {
  grep -oP '(?<=^switch-client -t ).*' "$CMDLOG" | tail -1
}

@test "next skips delegated agents and intake while preserving cockpit order" {
  cycle_from %1
  [ "$status" -eq 0 ]
  [ "$(switched_to)" = %4 ]
  cycle_from %4
  [ "$(switched_to)" = %7 ]
  cycle_from %7
  [ "$(switched_to)" = %1 ]
}

@test "prev skips delegated agents and intake and wraps" {
  cycle_from %4 prev
  [ "$(switched_to)" = %1 ]
  cycle_from %1 prev
  [ "$(switched_to)" = %7 ]
}

@test "excluded panes enter the ring at the directional edge" {
  cycle_from %2
  [ "$(switched_to)" = %1 ]
  cycle_from %5 prev
  [ "$(switched_to)" = %7 ]
}

@test "one eligible pane does not switch to itself but remains reachable" {
  printf '%%1|triage|\n%%2|worker|delegated\n%%5|intake|\n' > "$LIVE"
  cycle_from %1
  ! grep -q '^switch-client' "$CMDLOG"
  cycle_from %2
  [ "$(switched_to)" = %1 ]
}

@test "a trailing excluded pane does not abort the cycle" {
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" %%1 %%4 %%5\n' > "$STATE"
  cycle_from %1
  [ "$status" -eq 0 ]
  [ "$(switched_to)" = %4 ]
}

@test "no eligible panes does nothing" {
  printf '%%2|worker|delegated\n%%5|intake|\n' > "$LIVE"
  cycle_from %2
  [ "$status" -eq 0 ]
  ! grep -q '^switch-client' "$CMDLOG"
}

@test "empty cockpit and bad direction do not switch" {
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STATE"
  cycle_from %1
  [ "$status" -eq 0 ]
  ! grep -q '^switch-client' "$CMDLOG"
  cycle_from %1 --dry
  [ "$status" -eq 2 ]
  ! grep -q '^switch-client' "$CMDLOG"
}

@test "a warm cache is used without rendering the cockpit" {
  cycle_from %1
  printf '#!/usr/bin/env bash\nsleep 5\nexit 1\n' > "$STATE"
  start=$(date +%s%N)
  cycle_from %4
  elapsed=$(( ($(date +%s%N) - start) / 1000000 ))
  [ "$(switched_to)" = %7 ]
  [ "$elapsed" -lt 150 ]
}

@test "a stale cache is used now and refreshed in the background" {
  cycle_from %1
  touch -d '1 minute ago' "$BATS_TEST_TMPDIR/cache/order"
  printf '#!/usr/bin/env bash\nsleep 1\nprintf "%%s\\n" %%4 %%1\n' > "$STATE"
  cycle_from %1
  [ "$(switched_to)" = %4 ]
  for _ in $(seq 40); do
    [ "$(head -1 "$BATS_TEST_TMPDIR/cache/order")" = %4 ] && break
    sleep 0.1
  done
  [ "$(head -1 "$BATS_TEST_TMPDIR/cache/order")" = %4 ]
}

@test "dead panes and updated delegation metadata are filtered from a warm cache" {
  cycle_from %1
  printf '%%1|triage|\n%%4|homelab|delegated\n%%5|intake|\n%%7||\n' > "$LIVE"
  cycle_from %1
  [ "$(switched_to)" = %7 ]
}

@test "the selected agent pane is focused" {
  cycle_from %1
  grep -q '^select-window -t %4$' "$CMDLOG"
  grep -q '^select-pane -t %4$' "$CMDLOG"
}

@test "bindings keep the agent and normal session cyclers separate" {
  config="${BATS_TEST_DIRNAME}/../../.tmux.conf"
  grep -qE '^bind -n M-i run-shell .*__cycle_agent_session\.sh next' "$config"
  grep -qE '^bind -n M-, run-shell .*__cycle_agent_session\.sh prev' "$config"
  ! grep -E '^bind -n M-i ' "$config" | grep -q 'display-popup'
  ! grep -E '(M|C)-(PageUp|PageDown)' "$config" | grep -q __cycle_agent_session
}
