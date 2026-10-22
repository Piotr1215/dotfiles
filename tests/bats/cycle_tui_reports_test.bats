#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export TUI_REPORT_STATE_FILE="$BATS_TEST_TMPDIR/idx"
  export TUI_REPORT_TMUX="$BATS_TEST_TMPDIR/tmux"
  export TMUX_LOG="$BATS_TEST_TMPDIR/tmux.log"
  cat >"$TUI_REPORT_TMUX" <<'EOS'
#!/usr/bin/env bash
[[ "$1" == display-message ]] && { echo s:0.0; exit 0; }
printf '%s\n' "$*" >>"$TMUX_LOG"
EOS
  chmod +x "$TUI_REPORT_TMUX"
}

cycle_to() { # $1 = report index just before the wanted one
  printf '%s' "$1" >"$TUI_REPORT_STATE_FILE"
  run zsh "$repo_root/scripts/__cycle_tui_reports.sh"
  [ "$status" -eq 0 ]
}

@test "cycle reaches handoffs after byproject" {
  cycle_to 3
  grep -Fq -- "-T handoffs" "$TMUX_LOG"
}

@test "handoffs launches on the context-free rc" {
  cycle_to 3
  grep -Fq -- "taskwarrior-tui --taskrc $repo_root/scripts/../.config/taskwarrior-tui/handoffs.taskrc -r handoffs" "$TMUX_LOG"
}

@test "other reports launch without a custom rc" {
  cycle_to 0
  grep -Fq -- "taskwarrior-tui -r inbox" "$TMUX_LOG"
  ! grep -Fq -- "--taskrc" "$TMUX_LOG"
}

@test "cycle wraps from current back to inbox" {
  cycle_to 4
  grep -Fq -- "-T current" "$TMUX_LOG"
  cycle_to 5
  grep -Fq -- "-T inbox" "$TMUX_LOG"
}

@test "handoffs rc drops the context and enables the detail pane" {
  rc="$repo_root/.config/taskwarrior-tui/handoffs.taskrc"
  grep -qx 'context=none' "$rc"
  grep -qx 'uda.taskwarrior-tui.task-report.show-info=true' "$rc"
}

@test "handoffs report filters +piotr pending and sorts due then priority" {
  taskrc="$repo_root/.taskrc"
  grep -qx 'report.handoffs.filter=status:pending +piotr' "$taskrc"
  grep -qx 'report.handoffs.sort=due+,priority-' "$taskrc"
  grep -qx 'report.handoffs.columns=uuid.short,priority,due.relative,description.desc' "$taskrc"
}

@test "handoffs report lists a +piotr task under context work" {
  command -v task >/dev/null || skip "task not installed"
  d="$BATS_TEST_TMPDIR/task"; mkdir -p "$d"
  rc="$BATS_TEST_TMPDIR/rc"
  { grep -E '^(report\.handoffs|uda\.priority|context\.work)' "$repo_root/.taskrc"
    echo "data.location=$d"; echo "context=work"; echo "uda.priority.values=H,M,L,"
    echo "confirmation=off"; echo "verbose=nothing"; } >"$rc"
  export TASKRC="$rc" TASKDATA="$d"
  task add +work +piotr pri:L "low handoff" >/dev/null
  task add +work +piotr pri:H "high handoff" >/dev/null
  task add +work plain >/dev/null
  # context.work.read has -piotr: the plain report is empty, the rc override lists both.
  run task rc.context=none handoffs
  [ "$status" -eq 0 ]
  [[ "$output" == *"high handoff"* && "$output" == *"low handoff"* && "$output" != *plain* ]]
  [[ "${output%%low handoff*}" == *"high handoff"* ]]
}
