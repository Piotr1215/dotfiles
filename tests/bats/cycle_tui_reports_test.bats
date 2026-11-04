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
@test "old tui bridges once using a known pane title" {
  unset TASKWARRIOR_TUI_REPORT_REQUEST TASKWARRIOR_TUI_REPORT
  export TUI_REPORT_BINARY="$BATS_TEST_TMPDIR/tui" TMUX_PANE='%42' PATH="$BATS_TEST_TMPDIR:$PATH"
  printf '#!/bin/sh\nprintf "%%s\\n" byproject\n' > "$BATS_TEST_TMPDIR/tmux"
  printf '#!/bin/sh\nprintf "%%s %%s %%s\\n" "$TUI_REPORT_BRIDGE" "$1" "$2"\n' > "$TUI_REPORT_BINARY"
  chmod +x "$BATS_TEST_TMPDIR/tmux" "$TUI_REPORT_BINARY"
  run "$repo_root/scripts/__cycle_tui_reports.sh"
  [ "$status" -eq 0 ]; [ "$output" = '1 -r handoffs' ]
}
@test "unknown pane title falls back to cycling from inbox" {
  unset TASKWARRIOR_TUI_REPORT_REQUEST TASKWARRIOR_TUI_REPORT
  export TUI_REPORT_BINARY="$BATS_TEST_TMPDIR/tui" TMUX_PANE='%42' PATH="$BATS_TEST_TMPDIR:$PATH"
  printf '#!/bin/sh\nprintf "unknown\\n"\n' > "$BATS_TEST_TMPDIR/tmux"
  printf '#!/bin/sh\nprintf "%%s %%s\\n" "$1" "$2"\n' > "$TUI_REPORT_BINARY"
  chmod +x "$BATS_TEST_TMPDIR/tmux" "$TUI_REPORT_BINARY"
  run "$repo_root/scripts/__cycle_tui_reports.sh"
  [ "$status" -eq 0 ]; [ "$output" = '-r byrepo' ]
}
@test "bridge guard refuses recursive launches" {
  unset TASKWARRIOR_TUI_REPORT_REQUEST
  export TUI_REPORT_BRIDGE=1
  run "$repo_root/scripts/__cycle_tui_reports.sh"
  [ "$status" -ne 0 ]; [[ "$output" == *'upgraded taskwarrior-tui'* ]]
}
@test "invalid request fails instead of bridging" {
  export TASKWARRIOR_TUI_REPORT_REQUEST="$BATS_TEST_TMPDIR/missing"
  run "$repo_root/scripts/__cycle_tui_reports.sh"
  [ "$status" -ne 0 ]; [[ "$output" == *'Cannot write'* ]]
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
