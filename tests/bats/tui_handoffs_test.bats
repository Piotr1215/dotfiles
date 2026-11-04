#!/usr/bin/env bats
setup() {
  root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export TUI_TASK_COMMAND="$BATS_TEST_TMPDIR/task" TUI_TMUX_COMMAND="$BATS_TEST_TMPDIR/tmux" LOG="$BATS_TEST_TMPDIR/log"
  export TASKWARRIOR_TUI_REPORT=handoffs
  uuid=12345678-1234-1234-1234-123456789abc
  cat > "$TUI_TASK_COMMAND" <<'MOCK'
#!/usr/bin/env bash
if [[ "$*" == *export ]]; then
  if [[ -n "${TASK_JSON:-}" ]]; then printf '%s\n' "$TASK_JSON"; else printf '%s\n' '[{"uuid":"12345678-1234-1234-1234-123456789abc","description":"Test task","repo":"no-repo"}]'; fi
else
  printf '%s\n' "$*" >> "$LOG"
fi
MOCK
  cat > "$TUI_TMUX_COMMAND" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == list-panes ]]; then echo '%42 triage'; else printf '%s\n' "$*" >> "$LOG"; printf '%s' "$5" > "$LOG.payload"; fi
MOCK
  chmod +x "$TUI_TASK_COMMAND" "$TUI_TMUX_COMMAND"
}
@test "reply inserts the old full picker token without enter" {
  run "$root/scripts/__tui_dispatch.sh" 6 "$uuid"
  [ "$status" -eq 0 ]; grep -Fq '@"12345678-1234-1234-1234-123456789abc|-|no-repo|Test task"' "$LOG"
  grep -Fq '#{==:#{@agent_name},triage}' "$LOG"; grep -Fq 'paste-buffer -d -p' "$LOG"; grep -Fq 'switch-client -t %42' "$LOG"; ! grep -q 'C-m' "$LOG"
}
@test "spawn inserts the old spawn command and token with trailing space" {
  run "$root/scripts/__tui_dispatch.sh" 7 "$uuid"
  [ "$status" -eq 0 ]; grep -Fq '/ops-spawn-agent @"12345678-1234-1234-1234-123456789abc|-|no-repo|Test task" ' "$LOG"
  grep -Fq '#{==:#{@agent_name},triage}' "$LOG"; ! grep -q 'C-m' "$LOG"
}
@test "reply and spawn sanitize control characters without losing quotes or pipes" {
  export TASK_JSON='[{"uuid":"12345678-1234-1234-1234-123456789abc","description":"one\nsecond\rthird\u001bX | \"quoted\"","repo":"a\nb","linear_issue_id":"DEVOPS-1"}]'
  for key in 6 7; do
    run "$root/scripts/__tui_dispatch.sh" "$key" "$uuid"
    [ "$status" -eq 0 ]
    python3 - "$LOG.payload" <<'PYTEST'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
assert all(not (ord(c) < 32 or 127 <= ord(c) <= 159) for c in text)
assert 'a b|one second third X | "quoted"' in text
PYTEST
    ! grep -q 'C-m' "$LOG"
  done
}
@test "reply refuses a missing task and does not send" {
  printf '#!/bin/sh\nprintf "[]\\n"\n' > "$TUI_TASK_COMMAND"; chmod +x "$TUI_TASK_COMMAND"
  run "$root/scripts/__tui_dispatch.sh" 6 "$uuid"
  [ "$status" -ne 0 ]; [ ! -f "$LOG" ]
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
  run "$root/scripts/__tui_dispatch.sh" 8 "$uuid"
  [ "$status" -eq 0 ]; [[ "$output" == *'No action assigned'* ]]; [ ! -f "$LOG" ]
}

@test "handoff key 8 never creates an issue" {
  run "$root/scripts/__tui_dispatch.sh" 8 "$uuid"
  [ "$status" -eq 0 ]; [[ "$output" == *'No action assigned'* ]]; [ ! -f "$LOG" ]
}
