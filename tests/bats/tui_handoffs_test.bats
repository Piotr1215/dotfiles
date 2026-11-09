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
if [[ "$1" == list-panes ]]; then echo '%42 triage'; else printf '%s\n' "$*" >> "$LOG"; printf '%s' "$5" > "$LOG.payload"; printf '%s\0' "$@" > "$LOG.argv"; fi
MOCK
  export TUI_TW_WRAPPER="$BATS_TEST_TMPDIR/tw"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$LOG"\n' > "$TUI_TW_WRAPPER"
  chmod +x "$TUI_TASK_COMMAND" "$TUI_TMUX_COMMAND" "$TUI_TW_WRAPPER"
}
@test "ack opens a popup without writing or pasting" {
  run bash -c '"$1" 6 "$2" </dev/null' _ "$root/scripts/__tui_dispatch.sh" "$uuid"
  [ "$status" -eq 0 ]
  grep -Fq 'display-popup' "$LOG"
  ! grep -Eq '(^note |^done |paste-buffer|switch-client)' "$LOG"
}
@test "spawn inserts the old spawn command and token with trailing space" {
  run "$root/scripts/__tui_dispatch.sh" 7 "$uuid"
  [ "$status" -eq 0 ]; grep -Fq '/ops-spawn-agent @"12345678-1234-1234-1234-123456789abc|-|no-repo|Test task" ' "$LOG"
  grep -Fq '#{==:#{@agent_name},triage}' "$LOG"; ! grep -q 'C-m' "$LOG"
}
@test "later opens a wait-date popup without messaging or completing" {
  run "$root/scripts/__tui_dispatch.sh" 9 "$uuid"
  [ "$status" -eq 0 ]
  grep -Fq 'display-popup' "$LOG"
  grep -Fq 'Show handoff later' "$LOG"
  grep -Fq -- "--defer $uuid" "$LOG"
  ! grep -Eq '(paste-buffer|switch-client|^done )' "$LOG"
  grep -E '^uda.taskwarrior-tui.legend.handoffs=.*9 later' "$root/.taskrc"
  grep -E '^uda.taskwarrior-tui.legend.default=.*9 effort' "$root/.taskrc"
}
@test "handoff paste branches contain tmux command separators rather than escaped arguments" {
  for key in 7; do
    run "$root/scripts/__tui_dispatch.sh" "$key" "$uuid"
    [ "$status" -eq 0 ]
    python3 - "$LOG.argv" <<'PYTEST'
import pathlib, sys
args = pathlib.Path(sys.argv[1]).read_bytes().decode().split('\0')[:-1]
assert args[0] == 'set-buffer' and args[5:7] == [';', 'if-shell']
assert args[-3] == '#{==:#{@agent_name},triage}'
success, failure = args[-2:]
assert '\\;' not in success and '\\;' not in failure
assert [part.strip().split()[0] for part in success.split(';')] == ['set-option', 'paste-buffer', 'switch-client']
assert [part.strip().split()[0] for part in failure.split(';')] == ['delete-buffer', 'display-message']
assert 'paste-buffer -d -p' in success and 'switch-client -t %42' in success
PYTEST
  done
}
@test "spawn sanitizes control characters without losing quotes or pipes" {
  export TASK_JSON='[{"uuid":"12345678-1234-1234-1234-123456789abc","description":"one\nsecond\rthird\u001bX | \"quoted\"","repo":"a\nb","linear_issue_id":"DEVOPS-1"}]'
  for key in 7; do
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
@test "annotation on key 8 writes selected text" {
  run bash -c 'printf "new note\\n" | "$1" 8 "$2"' _ "$root/scripts/__tui_dispatch.sh" "$uuid"
  [ "$status" -eq 0 ]; grep -Fq 'annotate new note' "$LOG"
}
@test "key 4 opens the spawn dialog for the selected handoff without Gordon's pane" {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/scripts"
  printf '#!/usr/bin/env bash\nprintf "spawn %%s\\n" "$*" >> "$LOG"\n' > "$HOME/.claude/scripts/__spawn_claude_directive.sh"
  chmod +x "$HOME/.claude/scripts/__spawn_claude_directive.sh"
  run "$root/scripts/__tui_dispatch.sh" 4 "$uuid"
  [ "$status" -eq 0 ]; grep -qx "spawn $uuid" "$LOG"
  ! grep -Eq '(paste-buffer|switch-client|annotate)' "$LOG"
}

@test "missing report falls back to selected piotr tag" {
  unset TASKWARRIOR_TUI_REPORT
  cat > "$TUI_TASK_COMMAND" <<'MOCK'
#!/usr/bin/env bash
if [[ "$*" == *export ]]; then echo '[{"tags":["piotr"]}]'; else printf '%s\n' "$*" >> "$LOG"; fi
MOCK
  chmod +x "$TUI_TASK_COMMAND"
  run bash -c 'printf "tagged note\\n" | "$1" 8 "$2"' _ "$root/scripts/__tui_dispatch.sh" "$uuid"
  [ "$status" -eq 0 ]; grep -Fq 'annotate tagged note' "$LOG"
}

@test "handoff key 8 never creates an issue" {
  run bash -c '"$1" 8 "$2" </dev/null' _ "$root/scripts/__tui_dispatch.sh" "$uuid"
  [ "$status" -eq 0 ]; [ ! -f "$LOG" ]
}
@test "slot 2 cycles views from a handoff row without touching it" {
  export TASKWARRIOR_TUI_VIEW_VERSION=4 TASKWARRIOR_TUI_REPORT_REQUEST="$BATS_TEST_TMPDIR/request"
  : > "$TASKWARRIOR_TUI_REPORT_REQUEST"
  run "$root/scripts/__tui_dispatch.sh" 2 "$uuid"
  [ "$status" -eq 0 ]
  grep -qx current "$TASKWARRIOR_TUI_REPORT_REQUEST"
  [ ! -e "$LOG" ]
}
@test "slot 7 toggles the Linear backlog and slot 0 keeps the note picker" {
  grep -qx 'uda.taskwarrior-tui.shortcuts.0=~/dev/dotfiles/scripts/__tui_shortcut_0.sh' "$root/.taskrc"
  grep -qx 'uda.taskwarrior-tui.shortcuts.7=~/dev/dotfiles/scripts/__tui_shortcut_7.sh' "$root/.taskrc"
  grep -aE '^uda.taskwarrior-tui.legend.default=0 note .*7 backlog' "$root/.taskrc"
  grep -Fq '7) exec "$root/__toggle_linear_backlog.sh"' "$root/scripts/__tui_dispatch.sh"
}
@test "slot 2 is a configured foreground shortcut" {
  grep -q '^uda.taskwarrior-tui.shortcuts.2=~/dev/dotfiles/scripts/__tui_shortcut_2.sh$' "$root/.taskrc"
  grep -q '^uda.taskwarrior-tui.shortcuts.background=5,6,9$' "$root/.taskrc"
}

@test "handoffs legend lists the brief shortcut" {
  grep -a '^uda.taskwarrior-tui.legend.handoffs=' "$root/.taskrc" | grep -q 'b brief'
}
