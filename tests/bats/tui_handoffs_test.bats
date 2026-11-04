#!/usr/bin/env bats
setup() {
  root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export TUI_TASK_COMMAND="$BATS_TEST_TMPDIR/task" TUI_TMUX_COMMAND="$BATS_TEST_TMPDIR/tmux" LOG="$BATS_TEST_TMPDIR/log"
  export TASKWARRIOR_TUI_REPORT=handoffs
  uuid=12345678-1234-1234-1234-123456789abc
  cat > "$TUI_TASK_COMMAND" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$LOG"
MOCK
  cat > "$TUI_TMUX_COMMAND" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == list-panes ]]; then echo '%42 triage'; else printf '%s\n' "$*" >> "$LOG"; fi
MOCK
  chmod +x "$TUI_TASK_COMMAND" "$TUI_TMUX_COMMAND"
}
@test "ack saves comment then completes task" {
  run bash -c 'printf "Looks good\\n" | "$1" 7 "$2"' _ "$root/scripts/__tui_dispatch.sh" "$uuid"
  [ "$status" -eq 0 ]; grep -Fq 'annotate Looks good' "$LOG"; grep -Fq "$uuid done" "$LOG"
}
@test "reply guards pane and types a reference without enter" {
  run "$root/scripts/__tui_dispatch.sh" 6 "$uuid"
  [ "$status" -eq 0 ]; grep -Fq '#{==:#{@agent_name},triage}' "$LOG"; grep -Fq "@12345678 " "$LOG"; ! grep -q 'C-m' "$LOG"
}
@test "annotation writes selected text" {
  run bash -c 'printf "new note\\n" | "$1" 4 "$2"' _ "$root/scripts/__tui_dispatch.sh" "$uuid"
  [ "$status" -eq 0 ]; grep -Fq 'annotate new note' "$LOG"
}

@test "missing report falls back to selected piotr tag" {
  unset TASKWARRIOR_TUI_REPORT
  cat > "$TUI_TASK_COMMAND" <<'MOCK'
#!/usr/bin/env bash
if [[ "$*" == *export ]]; then echo '[{"tags":["piotr"]}]'; else printf '%s\n' "$*" >> "$LOG"; fi
MOCK
  chmod +x "$TUI_TASK_COMMAND"
  run bash -c 'printf "\n" | "$1" 7 "$2"' _ "$root/scripts/__tui_dispatch.sh" "$uuid"
  [ "$status" -eq 0 ]; grep -Fq "$uuid done" "$LOG"
}
