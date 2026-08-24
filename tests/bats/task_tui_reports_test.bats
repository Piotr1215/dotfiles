#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  taskdata="$BATS_TEST_TMPDIR/task"
  taskrc="$BATS_TEST_TMPDIR/taskrc"
  mkdir -p "$taskdata"

  {
    printf 'data.location=%s\n' "$taskdata"
    printf 'hooks=0\nconfirmation=0\nbulk=0\ncolor=off\n'
    grep -E '^(context\.(work|gordon)\.(read|write)|report\.(current|gordon)\.(columns|labels|sort|filter)|uda\.(follow|linear_issue_id|release|session|repo)\.(type|label|values))=' \
      "$repo_root/.taskrc"
  } >"$taskrc"
  export TASKDATA="$taskdata" TASKRC="$taskrc"

  task_cmd() {
    task "$@"
  }
}

capture_tui() {
  local report="$1"
  local context="$2"
  local socket="task-tui-$BATS_TEST_NUMBER-$report-$$"
  local tmux_tmpdir="$BATS_TEST_TMPDIR/tmux-$report"
  local pane=""
  local pane_id
  local tmux_pid
  mkdir -p "$tmux_tmpdir"

  task_cmd context "$context" >/dev/null 2>&1
  env TMUX_TMPDIR="$tmux_tmpdir" tmux -L "$socket" new-session -d -s report-test -x 120 -y 30 \
    "env TASKRC='$taskrc' TASKDATA='$taskdata' TASKWARRIOR_TUI_DATA='$BATS_TEST_TMPDIR/tui-state-$report' TERM=screen-256color NCURSES_NO_UTF8_ACS=1 taskwarrior-tui --report '$report'"
  tmux_pid="$(env TMUX_TMPDIR="$tmux_tmpdir" tmux -L "$socket" display-message -p '#{pid}')"
  [[ "$tmux_pid" =~ ^[0-9]+$ ]] || return 1
  pane_id="$(env TMUX_TMPDIR="$tmux_tmpdir" tmux -L "$socket" list-panes -t report-test -F '#{pane_id}' | head -n 1)"
  [[ "$pane_id" == %* ]] || return 1

  for _ in {1..30}; do
    pane="$(env TMUX_TMPDIR="$tmux_tmpdir" tmux -L "$socket" capture-pane -p -t "$pane_id")"
    [[ "$pane" == *"Filter Tasks"* ]] && break
    sleep 0.1
  done

  env TMUX_TMPDIR="$tmux_tmpdir" tmux -L "$socket" kill-server
  ! env TMUX_TMPDIR="$tmux_tmpdir" tmux -L "$socket" has-session 2>/dev/null || return 1
  printf '%s\n' "$pane"
}

@test "tui aliases select isolated work and gordon contexts" {
  grep -Fq "alias tuiw='task context work; TERM=screen-256color NCURSES_NO_UTF8_ACS=1 tui --report current'" \
    "$repo_root/.zsh_aliases"
  grep -Fq "alias tuig='task context gordon; TERM=screen-256color NCURSES_NO_UTF8_ACS=1 tui --report gordon'" \
    "$repo_root/.zsh_aliases"
}

@test "each tui displays its tag split in the report filter" {
  run task_cmd _get rc.report.current.filter
  [ "$status" -eq 0 ]
  [[ "$output" == *"-gordon"* ]]

  run task_cmd _get rc.report.gordon.filter
  [ "$status" -eq 0 ]
  [[ "$output" == *"+gordon"* ]]
}

@test "installed tui renders the distinct report filters" {
  run capture_tui current work
  [ "$status" -eq 0 ]
  [[ "$output" == *"-gordon"* ]] || {
    printf '%s\n' "$output" >&3
    false
  }

  run capture_tui gordon gordon
  [ "$status" -eq 0 ]
  [[ "$output" == *"+gordon"* ]] || {
    printf '%s\n' "$output" >&3
    false
  }
}

@test "work report excludes gordon tasks and gordon report isolates them" {
  task_cmd add +work "Piotr task"
  task_cmd add +work +gordon "Gordon task"

  task_cmd context work
  run task_cmd current
  [ "$status" -eq 0 ]
  [[ "$output" == *"Piotr task"* ]]
  [[ "$output" != *"Gordon task"* ]]

  task_cmd context gordon
  run task_cmd gordon
  [ "$status" -eq 0 ]
  [[ "$output" != *"Piotr task"* ]]
  [[ "$output" == *"Gordon task"* ]]
}

@test "each tui context tags newly created tasks for its own report" {
  task_cmd context work
  task_cmd add "Created from tuiw"
  run task_cmd +work -gordon count
  [ "$status" -eq 0 ]
  [ "$(grep -cx '1' <<<"$output")" -eq 1 ]

  task_cmd context gordon
  task_cmd add "Created from tuig"
  run task_cmd +gordon count
  [ "$status" -eq 0 ]
  [ "$(grep -cx '1' <<<"$output")" -eq 1 ]
}
