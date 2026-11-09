#!/usr/bin/env bats
setup() {
  root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  helper="$root/scripts/__tui_ack_handoff.sh"
  uuid=12345678-1234-1234-1234-123456789abc
  export LOG="$BATS_TEST_TMPDIR/log" INPUT_TEXT='literal $(touch /tmp/never) ; "quoted" | text'
  export TUI_TMUX_COMMAND="$BATS_TEST_TMPDIR/tmux" TUI_INPUT_COMMAND="$BATS_TEST_TMPDIR/input"
  export TUI_TW_WRAPPER="$BATS_TEST_TMPDIR/tw" TUI_SND_COMMAND="$BATS_TEST_TMPDIR/snd"
  for cmd in tmux input tw snd gum; do
    cat > "$BATS_TEST_TMPDIR/$cmd" <<'MOCK'
#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
with open(os.environ['LOG'], 'a') as f:
    f.write(json.dumps([name, sys.argv[1:], os.environ.get('SND_FROM')]) + '\n')
if name == 'input':
    print(os.environ.get('INPUT_TEXT', ''))
    sys.exit(int(os.environ.get('INPUT_STATUS', '0')))
if name == 'tw' and sys.argv[1] == 'done':
    if os.environ.get('TW_PIOTR_HANDOFF_CLOSE') != '1':
        print('missing human handoff close marker', file=sys.stderr)
        sys.exit(1)
    if os.environ.get('TW_DONE_OPEN_AGENTS_OK') != '1':
        print('open agent work', file=sys.stderr)
        sys.exit(1)
    if os.environ.get('DONE_FAIL'):
        print('another refusal', file=sys.stderr)
        sys.exit(17)
if name == os.environ.get('FAIL_COMMAND'):
    sys.exit(42)
MOCK
    chmod +x "$BATS_TEST_TMPDIR/$cmd"
  done
  export PATH="$BATS_TEST_TMPDIR:$PATH"
}
@test "normal invocation opens a popup with command and overrides" {
  run "$helper" "$uuid" </dev/null
  [ "$status" -eq 0 ]
  python3 - "$LOG" "$helper" "$uuid" <<'PY'
import json, os, shutil, sys
rows = [json.loads(x) for x in open(sys.argv[1])]
assert len(rows) == 1 and rows[0][0] == 'tmux'
a = rows[0][1]
assert a[0] == 'display-popup' and '-E' in a
assert any('Ack with comment' in s for s in a)
assert any('--comment' in s and sys.argv[3] in s and sys.argv[2] in s for s in a)
for name in ('TUI_INPUT_COMMAND', 'TUI_TW_WRAPPER', 'TUI_SND_COMMAND'):
    value = shutil.which(os.environ[name]) if name == 'TUI_INPUT_COMMAND' else os.environ[name]
    assert any(a[i:i+2] == ['-e', name + '=' + value] for i in range(len(a)-1))
assert not any('paste-buffer' in s for s in a)
PY
}
@test "popup receives the default input wrapper and sender paths" {
  unset TUI_INPUT_COMMAND TUI_TW_WRAPPER TUI_SND_COMMAND
  run "$helper" "$uuid" </dev/null
  [ "$status" -eq 0 ]
  python3 - "$LOG" <<'PY'
import json, os, shutil, sys
a = json.loads(open(sys.argv[1]).readline())[1]
for value in ('TUI_INPUT_COMMAND=' + shutil.which('gum'), 'TUI_TW_WRAPPER=' + os.path.expanduser('~/.claude/scripts/__tw.sh'), 'TUI_SND_COMMAND=' + os.path.expanduser('~/.claude/scripts/snd')):
    assert any(a[i:i+2] == ['-e', value] for i in range(len(a)-1))
PY
}
@test "comment sends literal text once between note and done" {
  run "$helper" --comment "$uuid"
  [ "$status" -eq 0 ]
  python3 - "$LOG" "$uuid" <<'PY'
import json, os, sys
r = [json.loads(x) for x in open(sys.argv[1])]
u, text = sys.argv[2], os.environ['INPUT_TEXT']
assert [x[0] for x in r] == ['input', 'tw', 'snd', 'tw']
assert r[0][1][0] == 'input'
assert r[1][1] == ['note', u, 'piotr-comment: ' + text]
assert r[2][1] == ['--no-human', '-t', 'triage', 'Piotr replied to handoff ' + u + ': ' + text]
assert r[2][2] == 'handoffs-tui'
assert r[3][1] == ['done', u]
PY
}
@test "cancel or blank input makes no writes" {
  for mode in escape interrupt empty whitespace; do
    rm -f "$LOG"
    export INPUT_STATUS=0 INPUT_TEXT=''
    case "$mode" in escape) INPUT_STATUS=1 ;; interrupt) INPUT_STATUS=130 ;; whitespace) INPUT_TEXT='   ' ;; esac
    run "$helper" --comment "$uuid"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$LOG")" -eq 1 ]
  done
}
@test "input failure propagates and makes no writes" {
  export INPUT_STATUS=7
  run "$helper" --comment "$uuid"
  [ "$status" -eq 7 ]; [ "$(wc -l < "$LOG")" -eq 1 ]
}
@test "note or sender failure stops the remaining operations" {
  for command in tw snd; do
    rm -f "$LOG"; export FAIL_COMMAND="$command"
    run "$helper" --comment "$uuid"
    [ "$status" -ne 0 ]
    python3 - "$LOG" "$command" <<'PY'
import json, sys
r = [json.loads(x)[0] for x in open(sys.argv[1])]
assert r == (['input', 'tw'] if sys.argv[2] == 'tw' else ['input', 'tw', 'snd'])
PY
  done
}
@test "invalid uuid is rejected before popup or input" {
  for mode in popup comment; do
    rm -f "$LOG"
    if [ "$mode" = popup ]; then run "$helper" invalid; else run "$helper" --comment invalid; fi
    [ "$status" -ne 0 ]; [ ! -e "$LOG" ]
  done
}

@test "open agent work does not block comment completion" {
  run "$helper" --comment "$uuid"
  [ "$status" -eq 0 ]
  python3 - "$LOG" <<'PYTEST'
import json, sys
r = [json.loads(x) for x in open(sys.argv[1])]
assert r[-1][0] == 'tw' and r[-1][1][0] == 'done'
PYTEST
}
@test "another done refusal reaches popup and triage" {
  export DONE_FAIL=1
  run "$helper" --comment "$uuid"
  [ "$status" -eq 17 ]
  [[ "$output" == *'another refusal'* ]]
  python3 - "$LOG" <<'PYTEST'
import json, sys
r = [json.loads(x) for x in open(sys.argv[1])]
assert r[-1][0] == 'snd' and 'another refusal' in r[-1][1][-1]
PYTEST
}
