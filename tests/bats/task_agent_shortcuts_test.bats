#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  fixture_bin="$BATS_TEST_TMPDIR/bin"
  task_log="$BATS_TEST_TMPDIR/task.log"
  mkdir -p "$fixture_bin"

  cat >"$fixture_bin/task" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "_tags" ]]; then
  printf '%s\n' "${TASK_TEST_TAGS:-}"
  exit 0
fi
printf '%s\n' "$*" >>"$TASK_TEST_LOG"
EOF
  chmod +x "$fixture_bin/task"
}

@test "agent toggle selects Codex and removes Claude" {
  run env PATH="$fixture_bin:$PATH" TASK_TEST_TAGS="work claude" \
    TASK_TEST_LOG="$task_log" \
    "$repo_root/.config/taskwarrior-tui/shortcut-scripts/__toggle_agent_label.sh" \
    codex task-uuid

  [ "$status" -eq 0 ]
  grep -Fq "task-uuid modify +codex -claude" "$task_log"
}

@test "agent toggle removes the selected runner when already present" {
  run env PATH="$fixture_bin:$PATH" TASK_TEST_TAGS="work codex" \
    TASK_TEST_LOG="$task_log" \
    "$repo_root/.config/taskwarrior-tui/shortcut-scripts/__toggle_agent_label.sh" \
    codex task-uuid

  [ "$status" -eq 0 ]
  grep -Fq "task-uuid modify -codex" "$task_log"
  ! grep -Fq "+claude" "$task_log"
}

@test "agent toggle rejects an unknown runner" {
  run env PATH="$fixture_bin:$PATH" TASK_TEST_LOG="$task_log" \
    "$repo_root/.config/taskwarrior-tui/shortcut-scripts/__toggle_agent_label.sh" \
    unknown task-uuid

  [ "$status" -ne 0 ]
  [ ! -e "$task_log" ]
}

@test "taskwarrior shortcuts keep 5 for Claude and assign 6 to Codex" {
  run grep -F "uda.taskwarrior-tui.shortcuts.5=~/.config/taskwarrior-tui/shortcut-scripts/__toggle_claude_label.sh" \
    "$repo_root/.taskrc"
  [ "$status" -eq 0 ]

  run grep -F "uda.taskwarrior-tui.shortcuts.6=~/.config/taskwarrior-tui/shortcut-scripts/__toggle_codex_label.sh" \
    "$repo_root/.taskrc"
  [ "$status" -eq 0 ]
}
