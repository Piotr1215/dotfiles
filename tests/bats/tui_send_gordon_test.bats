#!/usr/bin/env bats
setup() {
  root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export TUI_TASK_COMMAND="$BATS_TEST_TMPDIR/task" TUI_TMUX_COMMAND="$BATS_TEST_TMPDIR/tmux" LOG="$BATS_TEST_TMPDIR/log"
  uuid=12345678-1234-1234-1234-123456789abc
  export TASK_JSON='[{"uuid":"12345678-1234-1234-1234-123456789abc","description":"Test task","linear_issue_id":"DEVOPS-1","repo":"repo"}]'
  cat > "$TUI_TASK_COMMAND" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$TASK_JSON"
MOCK
  cat > "$TUI_TMUX_COMMAND" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == list-panes ]]; then
  printf '%s\n' "${PANES-%42 triage}"
else
  printf '%s\n' "$@" >> "$LOG"
  [[ "$1" != send-keys || "${SEND_FAIL:-0}" == 0 ]]
fi
MOCK
  chmod +x "$TUI_TASK_COMMAND" "$TUI_TMUX_COMMAND"
}

@test "sends the full packet without Enter then switches to Gordon's pane" {
  run "$root/scripts/__tui_send_gordon.sh" "$uuid"
  [ "$status" -eq 0 ]
  mapfile -t args < "$LOG"
  [ "${args[0]}" = send-keys ]; [ "${args[1]}" = -t ]; [ "${args[2]}" = %42 ]
  [ "${args[3]}" = -l ]; [ "${args[4]}" = -- ]
  [ "${args[5]}" = '@"12345678-1234-1234-1234-123456789abc|DEVOPS-1|repo|Test task" ' ]
  [ "${args[6]}" = switch-client ]; [ "${args[7]}" = -t ]; [ "${args[8]}" = %42 ]
  [ "${#args[@]}" -eq 9 ]
}

@test "failed paste does not switch panes" {
  export SEND_FAIL=1
  run "$root/scripts/__tui_send_gordon.sh" "$uuid"
  [ "$status" -ne 0 ]
  grep -Fxq send-keys "$LOG"
  ! grep -Fxq switch-client "$LOG"
}

@test "missing repo and Linear use packet defaults" {
  export TASK_JSON='[{"uuid":"12345678-1234-1234-1234-123456789abc","description":"Test"}]'
  run "$root/scripts/__tui_send_gordon.sh" "$uuid"
  [ "$status" -eq 0 ]; grep -Fxq '@"12345678-1234-1234-1234-123456789abc|-|no-repo|Test" ' "$LOG"
}

@test "blank repo and Linear use packet defaults after flattening" {
  export TASK_JSON='[{"uuid":"12345678-1234-1234-1234-123456789abc","description":"Test","linear_issue_id":" \t ","repo":"\n "}]'
  run "$root/scripts/__tui_send_gordon.sh" "$uuid"
  [ "$status" -eq 0 ]; grep -Fxq '@"12345678-1234-1234-1234-123456789abc|-|no-repo|Test" ' "$LOG"
}

@test "failed task export does not send" {
  printf '#!/bin/sh\nexit 1\n' > "$TUI_TASK_COMMAND"
  run "$root/scripts/__tui_send_gordon.sh" "$uuid"
  [ "$status" -ne 0 ]; [[ "$output" == *'Task export failed'* ]]; [ ! -e "$LOG" ]
}

@test "no Gordon pane fails without sending" {
  export PANES='%3 another'
  run "$root/scripts/__tui_send_gordon.sh" "$uuid"
  [ "$status" -ne 0 ]; [[ "$output" == *'Gordon pane not found'* ]]; [ ! -e "$LOG" ]
}

@test "missing or mismatched task and invalid UUID fail without sending" {
  for TASK_JSON in '[]' '[{"uuid":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","description":"other"}]' '[{"uuid":"12345678-1234-1234-1234-123456789abc","description":"one"},{"uuid":"12345678-1234-1234-1234-123456789abc","description":"two"}]'; do
    export TASK_JSON
    run "$root/scripts/__tui_send_gordon.sh" "$uuid"
    [ "$status" -ne 0 ]; [[ "$output" == *'Task not found'* ]]; [ ! -e "$LOG" ]
  done
  run "$root/scripts/__tui_send_gordon.sh" bad
  [ "$status" -ne 0 ]; [[ "$output" == *'full task UUID'* ]]; [ ! -e "$LOG" ]
}

@test "control characters are flattened while quotes and pipes remain" {
  export TASK_JSON='[{"uuid":"12345678-1234-1234-1234-123456789abc","description":"one\nsecond\rthird\u001bX | \"quoted\"","repo":"a\nb"}]'
  run "$root/scripts/__tui_send_gordon.sh" "$uuid"
  [ "$status" -eq 0 ]; grep -Fxq '@"12345678-1234-1234-1234-123456789abc|-|a b|one second third X | "quoted"" ' "$LOG"
}

@test "configuration binds Gordon and shows it in both legends" {
  grep -Fxq 'uda.taskwarrior-tui.gordon.command=~/dev/dotfiles/scripts/__tui_send_gordon.sh' "$root/.taskrc"
  grep -q '^uda.taskwarrior-tui.legend.default=.*\^G gordon' "$root/.taskrc"
  grep -q '^uda.taskwarrior-tui.legend.handoffs=.*\^G gordon' "$root/.taskrc"
}
