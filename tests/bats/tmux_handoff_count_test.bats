#!/usr/bin/env bats
setup() {
  script="${BATS_TEST_DIRNAME}/../../scripts/__tmux_handoff_count.sh"
  export TUI_HANDOFF_TASK_COMMAND="$BATS_TEST_TMPDIR/task" LOG="$BATS_TEST_TMPDIR/log"
  cat > "$TUI_HANDOFF_TASK_COMMAND" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$LOG"
printf '%s\n' "${COUNT:-2}"
MOCK
  chmod +x "$TUI_HANDOFF_TASK_COMMAND"
}
@test "count clears context and matches pending piotr report" {
  run "$script"
  [ "$status" -eq 0 ]; [ "$output" = ' H:2' ]
  grep -Fq 'rc.context=none rc.hooks=off rc.verbose=nothing status:pending +piotr count' "$LOG"
}
@test "invalid count is not shown" {
  export COUNT=invalid
  run "$script"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
