#!/usr/bin/env bats

setup() {
  fixture=$(mktemp -d)
  export TASKDATA="$fixture/data" TASKRC="$fixture/taskrc"
  mkdir "$TASKDATA"
  config="$BATS_TEST_DIRNAME/../../.taskrc"
  {
    printf 'confirmation=off\ncontext=work\ncontext.work.read=+work -private\n'
    sed -n '/^report\.private\./p; /^uda\.taskwarrior-tui\.report\.private\.context=/p' "$config"
  } > "$TASKRC"
  task rc.hooks=off add +private ordinary >/dev/null 2>&1
  task rc.hooks=off add +private blocked >/dev/null 2>&1
  task rc.hooks=off add +work other >/dev/null 2>&1
  task rc.hooks=off 2 modify depends:1 >/dev/null 2>&1
}

teardown() { rm -rf "$fixture"; }

@test 'private tui export includes blocked private tasks and leaves work context intact' {
  filter=$(task _get rc.report.private.filter)
  context=$(task show 2>/dev/null | awk '$1 == "uda.taskwarrior-tui.report.private.context" {print $2}')
  [ "$context" = none ]
  expected=$(task rc.context=none +private status:pending count 2>/dev/null)
  actual=$(task rc.json.array=on rc.confirmation=off rc.json.depends.array=on rc.color=off rc._forcecolor=off "rc.context=$context" "rc.report.private.filter=$filter" export private 2>/dev/null | jq length)
  [ "$expected" = 2 ]
  [ "$actual" = "$expected" ]
  [ "$(task +work status:pending count 2>/dev/null)" = 1 ]
}
