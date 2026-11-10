#!/usr/bin/env bats
# Key 0 in taskwarrior-tui switches tmux to the agent working on the selected task.
setup() {
  root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export TUI_TASK_COMMAND="$BATS_TEST_TMPDIR/task" TUI_TMUX_COMMAND="$BATS_TEST_TMPDIR/tmux" LOG="$BATS_TEST_TMPDIR/log"
  uuid=12345678-1234-1234-1234-123456789abc
  cat > "$TUI_TASK_COMMAND" <<'MOCK'
#!/usr/bin/env bash
if [[ "$*" == *export ]]; then printf '%s\n' "$TASK_JSON"; else printf 'task %s\n' "$*" >> "$LOG"; fi
MOCK
  # LIVE lists live session names; PANES_<session> holds "pane_id tag" lines.
  cat > "$TUI_TMUX_COMMAND" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
  has-session) [[ " $LIVE " == *" ${3#=} "* ]] ;;
  list-panes) var="PANES_${4#=}"; var=${var//-/_}; printf '%b' "${!var:-}" ;;
  *) printf '%s\n' "$*" >> "$LOG" ;;
esac
MOCK
  chmod +x "$TUI_TASK_COMMAND" "$TUI_TMUX_COMMAND"
  export TASK_JSON='[{"uuid":"12345678-1234-1234-1234-123456789abc","annotations":[
    {"entry":"20261108T124434Z","description":"tmux session old-run"},
    {"entry":"20261109T100000Z","description":"ledger-ok gone-session old-run (tmux has-session -t =old-run -> gone)"},
    {"entry":"20261110T080538Z","description":"tmux session directive-12345678"}]}]'
}

@test "jumps to the tagged agent pane of the newest live session, not the active pane" {
  export LIVE="old-run directive-12345678"
  export PANES_directive_12345678='%86 \n%85 directive-12345678\n'
  run "$root/scripts/__tui_dispatch.sh" 0 "$uuid"
  [ "$status" -eq 0 ]
  [ "$(cat "$LOG")" = 'switch-client -t %85' ]
}

@test "falls back to an older live session when the newest one is gone" {
  export LIVE="old-run"
  export PANES_old_run='%10 old-run\n'
  run "$root/scripts/__tui_dispatch.sh" 0 "$uuid"
  [ "$status" -eq 0 ]
  [ "$(cat "$LOG")" = 'switch-client -t %10' ]
}

@test "uses any tagged pane, then the session, when no pane carries the session name" {
  export LIVE="directive-12345678"
  export PANES_directive_12345678='%1 \n%2 other-agent\n'
  run "$root/scripts/__tui_jump_agent.sh" "$uuid"
  [ "$status" -eq 0 ]; [ "$(cat "$LOG")" = 'switch-client -t %2' ]
  rm -f "$LOG"
  export PANES_directive_12345678='%1 \n'
  run "$root/scripts/__tui_jump_agent.sh" "$uuid"
  [ "$status" -eq 0 ]; [ "$(cat "$LOG")" = 'switch-client -t =directive-12345678:' ]
}

@test "reports an error and does not switch when every recorded session is gone" {
  export LIVE=""
  run "$root/scripts/__tui_dispatch.sh" 0 "$uuid"
  [ "$status" -eq 1 ]
  [[ "$output" == *'No live agent session'*directive-12345678* ]]
  [ ! -e "$LOG" ]
}

@test "reports an error when the task records no session or none is selected" {
  export TASK_JSON='[{"uuid":"12345678-1234-1234-1234-123456789abc","annotations":[{"entry":"20261110T080538Z","description":"plain note"}]}]'
  run "$root/scripts/__tui_dispatch.sh" 0 "$uuid"
  [ "$status" -eq 1 ]; [[ "$output" == *'No agent session recorded'* ]]
  run "$root/scripts/__tui_dispatch.sh" 0
  [ "$status" -eq 1 ]; [[ "$output" == *'Select a task first'* ]]
  [ ! -e "$LOG" ]
}

@test "key 0 jumps before the handoff lookup and the legends and background list say so" {
  export TASKWARRIOR_TUI_REPORT=handoffs LIVE="directive-12345678"
  export PANES_directive_12345678='%85 directive-12345678\n'
  run "$root/scripts/__tui_dispatch.sh" 0 "$uuid"
  [ "$status" -eq 0 ]; [ "$(cat "$LOG")" = 'switch-client -t %85' ]
  grep -Eq '^uda.taskwarrior-tui.shortcuts.background=(.*,)?0(,|$)' "$root/.taskrc"
  for legend in default backlog handoffs; do
    grep -Eq "^uda.taskwarrior-tui.legend.${legend}=0 jump  " "$root/.taskrc"
  done
}
