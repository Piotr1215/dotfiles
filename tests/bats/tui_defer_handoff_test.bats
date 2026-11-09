#!/usr/bin/env bats
setup() {
  root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  helper="$root/scripts/__tui_defer_handoff.sh"
  uuid=12345678-1234-1234-1234-123456789abc
  export LOG="$BATS_TEST_TMPDIR/log" INPUT_TEXT=tomorrow
  export TUI_TMUX_COMMAND="$BATS_TEST_TMPDIR/tmux" TUI_INPUT_COMMAND="$BATS_TEST_TMPDIR/input"
  export TUI_TASK_COMMAND="$BATS_TEST_TMPDIR/task"
  for cmd in tmux input task; do
    cat > "$BATS_TEST_TMPDIR/$cmd" <<'MOCK'
#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
with open(os.environ['LOG'], 'a') as f:
    f.write(json.dumps([name, sys.argv[1:]]) + '\n')
if name == 'input':
    print(os.environ.get('INPUT_TEXT', ''))
    sys.exit(int(os.environ.get('INPUT_STATUS', '0')))
if name == 'task':
    if 'calc' in sys.argv:
        print(os.environ.get('DATE_IS_FUTURE', 'true'))
        sys.exit(int(os.environ.get('CALC_STATUS', '0')))
    sys.exit(int(os.environ.get('MODIFY_STATUS', '0')))
MOCK
    chmod +x "$BATS_TEST_TMPDIR/$cmd"
  done
}
@test "later opens a popup with UUID and command overrides" {
  run "$helper" "$uuid" </dev/null
  [ "$status" -eq 0 ]
  python3 - "$LOG" "$uuid" <<'PY'
import json, os, sys
r = [json.loads(x) for x in open(sys.argv[1])]
assert len(r) == 1 and r[0][0] == 'tmux'
a = r[0][1]
assert a[0] == 'display-popup' and '-EE' in a
assert ' Show handoff later ' in a
assert '--defer ' + sys.argv[2] in a[-1]
for name in ('TUI_INPUT_COMMAND', 'TUI_TASK_COMMAND'):
    assert any(a[i:i+2] == ['-e', name + '=' + os.environ[name]] for i in range(len(a)-1))
PY
}
@test "later sets only the selected task wait date" {
  run "$helper" --defer "$uuid"
  [ "$status" -eq 0 ]
  python3 - "$LOG" "$uuid" <<'PY'
import json, sys
r = [json.loads(x) for x in open(sys.argv[1])]
assert [x[0] for x in r] == ['input', 'task', 'task']
assert 'Show again: ' in r[0][1] and 'tomorrow' in r[0][1]
assert r[1][1] == ['rc.context=none', 'rc.hooks=off', 'calc', 'tomorrow > now']
assert r[2][1] == ['rc.context=none', 'rc.confirmation=off', sys.argv[2], 'modify', 'wait:tomorrow']
PY
}
@test "cancel or blank date makes no task calls" {
  for mode in escape interrupt empty whitespace; do
    rm -f "$LOG"
    export INPUT_STATUS=0 INPUT_TEXT=''
    case "$mode" in escape) INPUT_STATUS=1 ;; interrupt) INPUT_STATUS=130 ;; whitespace) INPUT_TEXT='   ' ;; esac
    run "$helper" --defer "$uuid"
    [ "$status" -eq 0 ]; [ "$(wc -l < "$LOG")" -eq 1 ]
  done
}
@test "input failure is reported without changing the task" {
  export INPUT_STATUS=7
  run "$helper" --defer "$uuid"
  [ "$status" -eq 7 ]; [ "$(wc -l < "$LOG")" -eq 1 ]
}
@test "invalid or past date is rejected before modifying" {
  for mode in invalid past; do
    rm -f "$LOG"
    export CALC_STATUS=0 DATE_IS_FUTURE=true
    case "$mode" in invalid) CALC_STATUS=2 ;; past) DATE_IS_FUTURE=false ;; esac
    run "$helper" --defer "$uuid"
    [ "$status" -ne 0 ]
    [[ "$output" == *'Choose a future date'* ]]
    [ "$(wc -l < "$LOG")" -eq 2 ]
  done
}
@test "wait modification failure propagates" {
  export MODIFY_STATUS=23
  run "$helper" --defer "$uuid"
  [ "$status" -eq 23 ]
}
@test "invalid UUID is rejected before popup or input" {
  for mode in popup defer; do
    rm -f "$LOG"
    if [ "$mode" = popup ]; then run "$helper" invalid; else run "$helper" --defer invalid; fi
    [ "$status" -ne 0 ]; [ ! -e "$LOG" ]
  done
}
@test "real wait hides the handoff then returns it without changing due date or completion" {
  export TUI_TASK_COMMAND="$(command -v task)"
  export TASKDATA="$BATS_TEST_TMPDIR/taskdata" TASKRC="$BATS_TEST_TMPDIR/taskrc"
  mkdir -p "$TASKDATA"
  printf 'data.location=%s\nhooks=off\nconfirmation=off\n' "$TASKDATA" > "$TASKRC"
  grep -E '^(report.handoffs.(columns|labels|sort|filter|description)|uda.kind.(type|label|values))=' "$root/.taskrc" >> "$TASKRC"
  "$TUI_TASK_COMMAND" add +piotr due:tomorrow 'Deferred handoff fixture' >/dev/null
  before=$("$TUI_TASK_COMMAND" export)
  uuid=$(jq -r '.[0].uuid' <<< "$before")
  run "$helper" --defer "$uuid"
  [ "$status" -eq 0 ]
  after=$("$TUI_TASK_COMMAND" "$uuid" export)
  jq -e --argjson before "$before" '.[0] | .status == "pending" and (.end | not) and (.tags | index("piotr") != null) and .due == $before[0].due and (.wait | length > 0)' <<< "$after"
  [ "$("$TUI_TASK_COMMAND" status:pending +piotr count)" -eq 0 ]
  run "$TUI_TASK_COMMAND" rc.context=none rc.color=off rc.defaultwidth=140 handoffs
  [[ "$output" == *'No matches.'* ]]
  run "$TUI_TASK_COMMAND" rc.context=none rc.color=off rc.defaultwidth=140 waiting
  [[ "$output" == *'Deferred handoff fixture'* ]]
  "$TUI_TASK_COMMAND" "$uuid" modify wait:yesterday >/dev/null
  [ "$("$TUI_TASK_COMMAND" status:pending +piotr count)" -eq 1 ]
  run "$TUI_TASK_COMMAND" rc.context=none rc.color=off rc.defaultwidth=140 handoffs
  [ "$status" -eq 0 ]; [[ "$output" == *'Deferred handoff fixture'* ]]
}
@test "real invalid date does not mutate the task or run shell text" {
  export TUI_TASK_COMMAND="$(command -v task)"
  export TASKDATA="$BATS_TEST_TMPDIR/taskdata" TASKRC="$BATS_TEST_TMPDIR/taskrc"
  mkdir -p "$TASKDATA"
  printf 'data.location=%s\nhooks=off\nconfirmation=off\n' "$TASKDATA" > "$TASKRC"
  "$TUI_TASK_COMMAND" add +piotr 'Untouched handoff fixture' >/dev/null
  before=$("$TUI_TASK_COMMAND" export)
  uuid=$(jq -r '.[0].uuid' <<< "$before")
  export INPUT_TEXT="tomorrow; touch $BATS_TEST_TMPDIR/injected"
  run "$helper" --defer "$uuid"
  [ "$status" -ne 0 ]; [ ! -e "$BATS_TEST_TMPDIR/injected" ]
  [ "$("$TUI_TASK_COMMAND" export)" = "$before" ]
}
