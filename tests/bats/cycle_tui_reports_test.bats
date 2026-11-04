#!/usr/bin/env bats
setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export TUI_REPORT_STATE_FILE="$BATS_TEST_TMPDIR/previous" TASKWARRIOR_TUI_REPORT_REQUEST="$BATS_TEST_TMPDIR/request"
  : > "$TASKWARRIOR_TUI_REPORT_REQUEST"
}
@test "cycle includes handoffs and wraps current to inbox" {
  export TASKWARRIOR_TUI_REPORT=byproject
  run "$repo_root/scripts/__cycle_tui_reports.sh"
  [ "$status" -eq 0 ]; grep -qx handoffs "$TASKWARRIOR_TUI_REPORT_REQUEST"
  export TASKWARRIOR_TUI_REPORT=handoffs
  run "$repo_root/scripts/__cycle_tui_reports.sh"
  [ "$status" -eq 0 ]; grep -qx current "$TASKWARRIOR_TUI_REPORT_REQUEST"
  export TASKWARRIOR_TUI_REPORT=current
  run "$repo_root/scripts/__cycle_tui_reports.sh"
  [ "$status" -eq 0 ]; grep -qx inbox "$TASKWARRIOR_TUI_REPORT_REQUEST"
}
@test "missing report request fails before changing state" {
  unset TASKWARRIOR_TUI_REPORT_REQUEST
  run "$repo_root/scripts/__cycle_tui_reports.sh"
  [ "$status" -ne 0 ]; [[ "$output" == *'upgraded taskwarrior-tui'* ]]; [ ! -e "$TUI_REPORT_STATE_FILE" ]
}
@test "handoffs overrides context and detail and legends are configured" {
  grep -qx 'uda.taskwarrior-tui.report.handoffs.context=none' "$repo_root/.taskrc"
  grep -qx 'uda.taskwarrior-tui.report.handoffs.show-info=true' "$repo_root/.taskrc"
  grep -q '^uda.taskwarrior-tui.legend.default=' "$repo_root/.taskrc"
  grep -q '^uda.taskwarrior-tui.legend.handoffs=' "$repo_root/.taskrc"
  for i in {1..9}; do grep -q "^uda.taskwarrior-tui.shortcuts.$i=.*__tui_shortcut_$i.sh" "$repo_root/.taskrc"; done
}

@test "handoffs report shows supported task IDs" {
  grep -qx 'report.handoffs.columns=id,priority,due.relative,description.desc' "$repo_root/.taskrc"
  grep -qx 'report.handoffs.labels=ID,P,Due,Desc' "$repo_root/.taskrc"
}
