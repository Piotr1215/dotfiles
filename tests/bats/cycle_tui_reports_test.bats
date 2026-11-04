#!/usr/bin/env bats
setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export TUI_REPORT_STATE_FILE="$BATS_TEST_TMPDIR/previous" TUI_REPORT_TMUX="$BATS_TEST_TMPDIR/tmux" TMUX_LOG="$BATS_TEST_TMPDIR/log"
  cat >"$TUI_REPORT_TMUX" <<'MOCK'
#!/usr/bin/env bash
[[ "$1" == display-message ]] && { echo '%1'; exit; }
printf '%s\n' "$*" >> "$TMUX_LOG"
MOCK
  chmod +x "$TUI_REPORT_TMUX"
}
@test "cycle skips handoffs and wraps current to inbox" {
  export TASKWARRIOR_TUI_REPORT=byproject
  run "$repo_root/scripts/__cycle_tui_reports.sh" cycle
  [ "$status" -eq 0 ]; grep -Fq -- '-T current' "$TMUX_LOG"
  export TASKWARRIOR_TUI_REPORT=current
  run "$repo_root/scripts/__cycle_tui_reports.sh" cycle
  [ "$status" -eq 0 ]; grep -Fq -- '-T inbox' "$TMUX_LOG"
}
@test "toggle returns to the prior report and handoffs clears context" {
  export TASKWARRIOR_TUI_REPORT=byrepo
  run "$repo_root/scripts/__cycle_tui_reports.sh" toggle
  [ "$status" -eq 0 ]; grep -Fq -- '--taskrc' "$TMUX_LOG"; grep -qx byrepo "$TUI_REPORT_STATE_FILE"
  export TASKWARRIOR_TUI_REPORT=handoffs
  run "$repo_root/scripts/__cycle_tui_reports.sh" toggle
  [ "$status" -eq 0 ]; grep -Fq -- '-T byrepo' "$TMUX_LOG"
  grep -qx 'context=none' "$repo_root/.config/taskwarrior-tui/handoffs.taskrc"
}
@test "legends and slots are configured per report" {
  grep -q '^uda.taskwarrior-tui.legend.default=' "$repo_root/.taskrc"
  grep -q '^uda.taskwarrior-tui.legend.handoffs=' "$repo_root/.taskrc"
  for i in {1..9}; do grep -q "^uda.taskwarrior-tui.shortcuts.$i=.*__tui_shortcut_$i.sh" "$repo_root/.taskrc"; done
}
