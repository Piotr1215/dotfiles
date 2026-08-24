#!/usr/bin/env bats

setup() {
  repo_root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  taskdata="$BATS_TEST_TMPDIR/task"
  taskrc="$BATS_TEST_TMPDIR/taskrc"
  mkdir -p "$taskdata"

  {
    printf 'data.location=%s\n' "$taskdata"
    printf 'hooks=0\nconfirmation=0\nbulk=0\ncolor=off\n'
    grep -E '^(context\.(work|gordon)\.(read|write)|report\.current\.(columns|labels|sort|filter)|uda\.(follow|linear_issue_id|release|session|repo)\.(type|label|values))=' \
      "$repo_root/.taskrc"
  } >"$taskrc"
  export TASKDATA="$taskdata" TASKRC="$taskrc"

  task_cmd() {
    task "$@"
  }
}

@test "tui aliases select isolated work and gordon contexts" {
  grep -Fq "alias tuiw='task context work; TERM=screen-256color NCURSES_NO_UTF8_ACS=1 tui --report current'" \
    "$repo_root/.zsh_aliases"
  grep -Fq "alias tuig='task context gordon; TERM=screen-256color NCURSES_NO_UTF8_ACS=1 tui --report current'" \
    "$repo_root/.zsh_aliases"
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
  run task_cmd current
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
