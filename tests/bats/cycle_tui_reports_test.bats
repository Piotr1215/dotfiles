#!/usr/bin/env bats
setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export TUI_REPORT_STATE_FILE="$BATS_TEST_TMPDIR/previous" TASKWARRIOR_TUI_REPORT_REQUEST="$BATS_TEST_TMPDIR/request"
  export TASKWARRIOR_TUI_VIEW_VERSION=2
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
@test "v2 uses its request even inside the bridge and preserves taskrc" {
  export TUI_REPORT_BRIDGE=2 TASKWARRIOR_TUI_REPORT=handoffs TASKRC="$BATS_TEST_TMPDIR/custom"
  run "$repo_root/scripts/__cycle_tui_reports.sh"
  [ "$status" -eq 0 ]; grep -qx current "$TASKWARRIOR_TUI_REPORT_REQUEST"; [ ! -e "$TASKRC" ]
}
@test "old tui bridges once using a known pane title" {
  unset TASKWARRIOR_TUI_REPORT_REQUEST TASKWARRIOR_TUI_REPORT
  export TUI_REPORT_BINARY="$BATS_TEST_TMPDIR/tui" TMUX_PANE='%42' PATH="$BATS_TEST_TMPDIR:$PATH"
  printf '#!/bin/sh\nprintf "%%s\\n" byproject\n' > "$BATS_TEST_TMPDIR/tmux"
  printf '#!/bin/sh\nprintf "%%s %%s %%s\\n" "$TUI_REPORT_BRIDGE" "$1" "$2"\n' > "$TUI_REPORT_BINARY"
  chmod +x "$BATS_TEST_TMPDIR/tmux" "$TUI_REPORT_BINARY"
  run "$repo_root/scripts/__cycle_tui_reports.sh"
  [ "$status" -eq 0 ]; [ "$output" = '2 -r handoffs' ]
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
@test "bridge clears the legacy handoffs rc for work reports" {
  unset TASKWARRIOR_TUI_REPORT_REQUEST
  export TASKWARRIOR_TUI_REPORT=handoffs TUI_REPORT_BINARY="$BATS_TEST_TMPDIR/tui"
  ln -s "$repo_root/.config/taskwarrior-tui/handoffs.taskrc" "$BATS_TEST_TMPDIR/legacy-rc"
  export TASKRC="$BATS_TEST_TMPDIR/legacy-rc"
  printf '#!/bin/sh\nprintf "%%s|%%s %%s\\n" "$TASKRC" "$1" "$2"\n' > "$TUI_REPORT_BINARY"
  chmod +x "$TUI_REPORT_BINARY"
  run "$repo_root/scripts/__cycle_tui_reports.sh"
  [ "$status" -eq 0 ]; [ "$output" = "$HOME/.taskrc|-r current" ]
}
@test "bridge preserves unrelated custom taskrc" {
  unset TASKWARRIOR_TUI_REPORT_REQUEST
  export TASKWARRIOR_TUI_REPORT=handoffs TUI_REPORT_BINARY="$BATS_TEST_TMPDIR/tui" TASKRC="$BATS_TEST_TMPDIR/custom-rc"
  : > "$TASKRC"
  printf '#!/bin/sh\nprintf "%%s\\n" "$TASKRC"\n' > "$TUI_REPORT_BINARY"
  chmod +x "$TUI_REPORT_BINARY"
  run "$repo_root/scripts/__cycle_tui_reports.sh"
  [ "$status" -eq 0 ]; [ "$output" = "$TASKRC" ]
}
@test "bridge 2 without a fingerprint upgrades" {
  unset TASKWARRIOR_TUI_REPORT_REQUEST TUI_REPORT_BRIDGE_BINARY
  export TUI_REPORT_BRIDGE=2 TUI_REPORT_BINARY="$BATS_TEST_TMPDIR/tui"
  printf '#!/bin/sh\nprintf "upgraded\\n"\n' > "$TUI_REPORT_BINARY"; chmod +x "$TUI_REPORT_BINARY"
  run "$repo_root/scripts/__cycle_tui_reports.sh"
  [ "$status" -eq 0 ]; [ "$output" = upgraded ]
}
@test "bridge refuses the same binary fingerprint" {
  unset TASKWARRIOR_TUI_REPORT_REQUEST
  export TUI_REPORT_BRIDGE=2 TUI_REPORT_BINARY="$BATS_TEST_TMPDIR/tui"
  printf '#!/bin/sh\nexit 0\n' > "$TUI_REPORT_BINARY"; chmod +x "$TUI_REPORT_BINARY"
  export TUI_REPORT_BRIDGE_BINARY="$(sha256sum "$TUI_REPORT_BINARY" | cut -d ' ' -f 1)"
  run "$repo_root/scripts/__cycle_tui_reports.sh"
  [ "$status" -ne 0 ]; [[ "$output" == *'upgraded taskwarrior-tui'* ]]
}
@test "bridge permits a changed binary fingerprint" {
  unset TASKWARRIOR_TUI_REPORT_REQUEST
  export TUI_REPORT_BRIDGE=2 TUI_REPORT_BRIDGE_BINARY=previous TUI_REPORT_BINARY="$BATS_TEST_TMPDIR/tui"
  printf '#!/bin/sh\nprintf "%%s\\n" "$TUI_REPORT_BRIDGE_BINARY"\n' > "$TUI_REPORT_BINARY"; chmod +x "$TUI_REPORT_BINARY"
  run "$repo_root/scripts/__cycle_tui_reports.sh"
  [ "$status" -eq 0 ]; [ "$output" = "$(sha256sum "$TUI_REPORT_BINARY" | cut -d ' ' -f 1)" ]
}
@test "v1 with a request upgrades once even from an earlier bridge" {
  export TASKWARRIOR_TUI_VIEW_VERSION=1 TUI_REPORT_BRIDGE=1 TASKWARRIOR_TUI_REPORT=byrepo TUI_REPORT_BINARY="$BATS_TEST_TMPDIR/tui"
  printf '#!/bin/sh\nprintf "%%s %%s %%s\\n" "$TUI_REPORT_BRIDGE" "$1" "$2"\n' > "$TUI_REPORT_BINARY"
  chmod +x "$TUI_REPORT_BINARY"
  run "$repo_root/scripts/__cycle_tui_reports.sh"
  [ "$status" -eq 0 ]; [ "$output" = '2 -r byproject' ]
  [ ! -s "$TASKWARRIOR_TUI_REPORT_REQUEST" ]
}
@test "invalid v2 request and same fingerprint fails rather than nesting" {
  export TASKWARRIOR_TUI_REPORT_REQUEST="$BATS_TEST_TMPDIR/missing" TUI_REPORT_BRIDGE=2 TUI_REPORT_BINARY="$BATS_TEST_TMPDIR/tui"
  printf '#!/bin/sh\nexit 0\n' > "$TUI_REPORT_BINARY"; chmod +x "$TUI_REPORT_BINARY"
  export TUI_REPORT_BRIDGE_BINARY="$(sha256sum "$TUI_REPORT_BINARY" | cut -d ' ' -f 1)"
  run "$repo_root/scripts/__cycle_tui_reports.sh"
  [ "$status" -ne 0 ]; [[ "$output" == *'upgraded taskwarrior-tui'* ]]
}
@test "handoffs overrides context and detail and legends are configured" {
  grep -qx 'uda.taskwarrior-tui.report.handoffs.context=none' "$repo_root/.taskrc"
  grep -qx 'uda.taskwarrior-tui.report.handoffs.show-info=false' "$repo_root/.taskrc"
  grep -qx 'uda.taskwarrior-tui.shortcuts.background=5,6,9' "$repo_root/.taskrc"
  grep -q '^uda.taskwarrior-tui.legend.default=' "$repo_root/.taskrc"
  grep -q '^uda.taskwarrior-tui.legend.handoffs=.*d done.*z details' "$repo_root/.taskrc"
  grep -qx 'uda.taskwarrior-tui.task-report.show-info=false' "$repo_root/.config/taskwarrior-tui/handoffs.taskrc"
  ! grep -q '^uda.taskwarrior-tui.shortcuts.z=' "$repo_root/.taskrc"
  for i in {1..9}; do grep -q "^uda.taskwarrior-tui.shortcuts.$i=.*__tui_shortcut_$i.sh" "$repo_root/.taskrc"; done
}

@test "handoffs report shows supported task IDs" {
  grep -qx 'report.handoffs.columns=id,priority,due.relative,description.desc' "$repo_root/.taskrc"
  grep -qx 'report.handoffs.labels=ID,P,Due,Desc' "$repo_root/.taskrc"
}
