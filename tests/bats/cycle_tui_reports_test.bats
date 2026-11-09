#!/usr/bin/env bats
setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export TUI_REPORT_STATE_FILE="$BATS_TEST_TMPDIR/previous" TASKWARRIOR_TUI_REPORT_REQUEST="$BATS_TEST_TMPDIR/request"
  export TASKWARRIOR_TUI_VIEW_VERSION=4
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
@test "v4 uses its request even inside the bridge and preserves taskrc" {
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
@test "v2 with a request upgrades through the bridge" {
  export TASKWARRIOR_TUI_VIEW_VERSION=2 TASKWARRIOR_TUI_REPORT=byrepo TUI_REPORT_BINARY="$BATS_TEST_TMPDIR/tui"
  printf '#!/bin/sh\nprintf "%%s %%s\\n" "$1" "$2"\n' > "$TUI_REPORT_BINARY"
  chmod +x "$TUI_REPORT_BINARY"
  run "$repo_root/scripts/__cycle_tui_reports.sh"
  [ "$status" -eq 0 ]; [ "$output" = '-r byproject' ]; [ ! -s "$TASKWARRIOR_TUI_REPORT_REQUEST" ]
}
@test "v3 with a request upgrades through the bridge" {
  export TASKWARRIOR_TUI_VIEW_VERSION=3 TASKWARRIOR_TUI_REPORT=byrepo TUI_REPORT_BINARY="$BATS_TEST_TMPDIR/tui"
  printf '#!/bin/sh\nprintf "%%s %%s\\n" "$1" "$2"\n' > "$TUI_REPORT_BINARY"
  chmod +x "$TUI_REPORT_BINARY"
  run "$repo_root/scripts/__cycle_tui_reports.sh"
  [ "$status" -eq 0 ]; [ "$output" = '-r byproject' ]; [ ! -s "$TASKWARRIOR_TUI_REPORT_REQUEST" ]
}
@test "invalid v4 request and same fingerprint fails rather than nesting" {
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
  grep -q '^uda.taskwarrior-tui.legend.default=.*\^P project' "$repo_root/.taskrc"
  grep -q '^uda.taskwarrior-tui.legend.handoffs=.*d done.*z details.*\^P project' "$repo_root/.taskrc"
  grep -q '^uda.taskwarrior-tui.legend.default=.*r reports.*\^R refresh' "$repo_root/.taskrc"
  grep -q '^uda.taskwarrior-tui.legend.handoffs=.*4 spawn.*7 gordon spawn.*8 annotate.*r reports.*\^R refresh' "$repo_root/.taskrc"
  grep -qx 'uda.taskwarrior-tui.task-report.show-info=false' "$repo_root/.config/taskwarrior-tui/handoffs.taskrc"
  ! grep -q '^uda.taskwarrior-tui.shortcuts.z=' "$repo_root/.taskrc"
  for i in 1 2 3 4 5 6 7 8 9; do grep -q "^uda.taskwarrior-tui.shortcuts.$i=.*__tui_shortcut_$i.sh" "$repo_root/.taskrc"; done
}

@test "handoffs report shows supported task IDs and the kind column" {
  grep -qx 'report.handoffs.columns=id,priority,due.relative,kind,description.desc' "$repo_root/.taskrc"
  grep -qx 'report.handoffs.labels=ID,P,Due,Kind,Desc' "$repo_root/.taskrc"
  grep -qx 'uda.kind.values=slack,command,pr,ack,other' "$repo_root/.taskrc"
  # piotr_step stays a field: the brief still reads it.
  grep -qx 'uda.piotr_step.type=string' "$repo_root/.taskrc"
  grep -q '^uda.taskwarrior-tui.legend.handoffs=.*d done  s kind action  z details' "$repo_root/.taskrc"
}

@test "frequent reports have the intended picker order" {
  for entry in inbox:1 handoffs:2 current:3 byrepo:4 byproject:5; do
    grep -qx "uda.taskwarrior-tui.report.${entry%:*}.order=${entry#*:}" "$repo_root/.taskrc"
  done
}

@test "handoffs report renders kind and legacy rows" {
  command -v task >/dev/null || skip "task is not installed"
  export TASKDATA="$BATS_TEST_TMPDIR/taskdata" TASKRC="$BATS_TEST_TMPDIR/taskrc"
  mkdir -p "$TASKDATA"
  printf 'data.location=%s\nhooks=off\nconfirmation=off\n' "$TASKDATA" > "$TASKRC"
  grep -E '^(report.handoffs.(columns|labels|sort|filter|description)|uda.(piotr_step|kind).(type|label|values))=' "$repo_root/.taskrc" >> "$TASKRC"
  task rc.confirmation=off add +piotr 'piotr_step:click Approve' kind:command 'A handoff' >/dev/null
  task rc.confirmation=off add +piotr 'Legacy handoff' >/dev/null
  run task rc.context=none rc.color=off rc.defaultwidth=140 handoffs
  [ "$status" -eq 0 ]
  [[ "$output" == *'Kind'* ]]; [[ "$output" != *'Your step'* ]]
  [[ "$output" == *'command'*'A handoff'* ]]; [[ "$output" == *'Legacy handoff'* ]]
  [[ "$output" != *'click Approve'* ]]
  run task rc.confirmation=off add +piotr kind:bogus 'Bad kind'
  [ "$status" -ne 0 ]
}

# Every view's legend reads digits in order, then letters, then control keys,
# and lists key 2 (the view cycle) and b (the brief) among them.
@test "legends list 2 and keep digits, letters and control keys in order" {
  legends=$(grep -a '^uda.taskwarrior-tui.legend\.' "$repo_root/.taskrc")
  [ "$(printf '%s\n' "$legends" | wc -l)" -ge 2 ]
  while IFS= read -r line; do
    legend=${line#*=}
    [[ "$legend" == *'1 open  2 next view  3 '* ]] || { echo "key 2 missing: $line"; return 1; }
    rank=0 last_digit=-1 first_letter=
    while IFS= read -r entry; do
      key=${entry%% *}
      case "$key" in
        [0-9]) (( rank == 0 )) || { echo "digit after letters: $entry in $line"; return 1; }
               (( key > last_digit )) || { echo "digits out of order: $entry in $line"; return 1; }
               last_digit=$key ;;
        [a-z]) (( rank <= 1 )) || { echo "letter after control keys: $entry in $line"; return 1; }
               [[ -n "$first_letter" ]] || first_letter=$entry
               rank=1 ;;
        ^?) rank=2 ;;
        *) echo "unexpected legend entry: $entry"; return 1 ;;
      esac
    done < <(printf '%s\n' "$legend" | sed 's/  /\n/g')
    [[ "$first_letter" == 'b brief' ]] || { echo "b brief must open the letter run: $line"; return 1; }
  done <<<"$legends"
}
