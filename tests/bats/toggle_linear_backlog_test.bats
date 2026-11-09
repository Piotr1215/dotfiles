#!/usr/bin/env bats

# __toggle_linear_backlog.sh (taskwarrior-tui key 7). Piotr, 9 Nov 2026: in
# tuiw the key moves the selected task's Linear issue to Backlog, and in the
# backlog report it does the opposite. Runs against a throwaway Taskwarrior DB
# with hooks off; mock curl keeps the issue state in a file so the confirming
# re-query sees the mutation.

setup() {
  root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  script="$root/scripts/__toggle_linear_backlog.sh"
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN" "$BATS_TEST_TMPDIR/data"
  export TASKDATA="$BATS_TEST_TMPDIR/data" TASKRC="$BATS_TEST_TMPDIR/taskrc"
  cat > "$TASKRC" <<EOF
data.location=$TASKDATA
hooks=off
confirmation=off
verbose=nothing
news.version=3.3.0
uda.linear_issue_id.type=string
uda.linear_issue_id.label=Linear Issue ID
EOF
  export CURL_LOG="$BATS_TEST_TMPDIR/curl.log" AUTH_LOG="$BATS_TEST_TMPDIR/auth.log" ARGV_LOG="$BATS_TEST_TMPDIR/argv.log"
  export STATE_FILE="$BATS_TEST_TMPDIR/state" NOTIFY_LOG="$BATS_TEST_TMPDIR/notify.log" PASS_LOG="$BATS_TEST_TMPDIR/pass.log"
  export STATES='[{"id":"s-backlog","name":"Backlog"},{"id":"s-todo","name":"Todo"},{"id":"s-prog","name":"In Progress"}]'
  export LINEAR_API_KEY=test-key
  unset TASKWARRIOR_TUI_REPORT UPDATE_FAIL
  printf 's-prog\tIn Progress\n' > "$STATE_FILE"

  cat > "$BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$ARGV_LOG"
while [ $# -gt 0 ]; do
  case "$1" in
    -H) [[ "$2" == @* ]] && cat "${2#@}" >> "$AUTH_LOG"; shift ;;
    --data) body="$2"; printf '%s\n' "$2" | jq -c . >> "$CURL_LOG"; shift ;;
  esac
  shift
done
IFS=$'\t' read -r sid sname < "$STATE_FILE"
case "$body" in
  *IssueStates*)
    jq -cn --arg sid "$sid" --arg sname "$sname" --argjson states "$STATES" \
      '{data:{issue:{id:"issue-uuid",state:{id:$sid,name:$sname},team:{states:{nodes:$states,pageInfo:{hasNextPage:false}}}}}}' ;;
  *MoveIssue*)
    [ -z "${UPDATE_FAIL:-}" ] || exit 22
    new=$(jq -r '.variables.state' <<<"$body")
    printf '%s\t%s\n' "$new" "$(jq -r --arg id "$new" '.[] | select(.id == $id) | .name' <<<"$STATES")" > "$STATE_FILE"
    echo '{"data":{"issueUpdate":{"success":true}}}' ;;
  *IssueState*)
    jq -cn --arg sid "$sid" --arg sname "$sname" '{data:{issue:{state:{id:$sid,name:$sname}}}}' ;;
esac
EOF
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$NOTIFY_LOG"\n' > "$BIN/notify-send"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$PASS_LOG"\nprintf "pass-key\\nlogin: x\\n"\n' > "$BIN/pass"
  chmod +x "$BIN/curl" "$BIN/notify-send" "$BIN/pass"
  export PATH="$BIN:$PATH"
}

# Adds a task and prints its UUID.
add_task() {
  task add "$@" >/dev/null
  task +LATEST uuids
}

tags_of() { task _get "$1.tags"; }

@test "tuiw task moves to Backlog and gains +backlog without +fresh" {
  uuid=$(add_task 'ship the thing' linear_issue_id:DEVOPS-1820 +fresh +work)
  export TASKWARRIOR_TUI_REPORT=current
  run "$script" "$uuid"
  [ "$status" -eq 0 ]
  [[ "$output" == *'DEVOPS-1820: In Progress -> Backlog'* ]]
  [ "$(sed -n 1p "$CURL_LOG" | jq -r '.variables.id')" = DEVOPS-1820 ]
  [ "$(sed -n 2p "$CURL_LOG" | jq -r '.variables.state')" = s-backlog ]
  [ "$(jq -s 'length' "$CURL_LOG")" = 3 ]
  [ "$(tags_of "$uuid")" = 'backlog,work' ]
  grep -q 'Backlog' "$NOTIFY_LOG"
}

@test "backlog report task moves to Todo and loses +backlog" {
  printf 's-backlog\tBacklog\n' > "$STATE_FILE"
  uuid=$(add_task 'later' linear_issue_id:DEVOPS-1821 +backlog +work)
  export TASKWARRIOR_TUI_REPORT=backlog
  run "$script" "$uuid"
  [ "$status" -eq 0 ]
  [[ "$output" == *'DEVOPS-1821: Backlog -> Todo'* ]]
  [ "$(sed -n 2p "$CURL_LOG" | jq -r '.variables.state')" = s-todo ]
  [ "$(tags_of "$uuid")" = work ]
}

@test "the toggle follows the task tag outside the backlog report" {
  uuid=$(add_task 'tagged' linear_issue_id:DEVOPS-1822 +backlog)
  run "$script" "$uuid"
  [ "$status" -eq 0 ]
  [ "$(sed -n 2p "$CURL_LOG" | jq -r '.variables.state')" = s-todo ]
  [ -z "$(tags_of "$uuid")" ]
}

@test "a triage task in the backlog report also moves to Todo" {
  uuid=$(add_task 'triage only' linear_issue_id:DEVOPS-1823 +triage)
  export TASKWARRIOR_TUI_REPORT=backlog
  run "$script" "$uuid"
  [ "$status" -eq 0 ]
  [ "$(sed -n 2p "$CURL_LOG" | jq -r '.variables.state')" = s-todo ]
  [ "$(tags_of "$uuid")" = triage ]
}

@test "a task without a Linear issue is skipped" {
  uuid=$(add_task 'no issue here' +work)
  run "$script" "$uuid"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Skipped no issue here: no linear_issue_id'* ]]
  [ ! -s "$CURL_LOG" ]
  [ "$(tags_of "$uuid")" = work ]
}

@test "several selected tasks are handled one by one" {
  a=$(add_task 'first' linear_issue_id:DEVOPS-1 +work)
  b=$(add_task 'second' +work)
  run "$script" "$a" "$b"
  [ "$status" -eq 0 ]
  [[ "$output" == *'DEVOPS-1: In Progress -> Backlog'* ]]
  [[ "$output" == *'Skipped second'* ]]
  [ "$(tags_of "$a")" = 'backlog,work' ]
}

@test "an issue already in the target state only syncs the tag" {
  printf 's-backlog\tBacklog\n' > "$STATE_FILE"
  uuid=$(add_task 'already' linear_issue_id:DEVOPS-1824)
  run "$script" "$uuid"
  [ "$status" -eq 0 ]
  [ "$(jq -s 'length' "$CURL_LOG")" = 1 ]
  [ "$(tags_of "$uuid")" = backlog ]
}

@test "a failed Linear update leaves the task untouched" {
  uuid=$(add_task 'fails' linear_issue_id:DEVOPS-1825 +fresh)
  export UPDATE_FAIL=1
  run "$script" "$uuid"
  [ "$status" -eq 1 ]
  [[ "$output" == *'DEVOPS-1825: Linear update failed'* ]]
  [ "$(tags_of "$uuid")" = fresh ]
  grep -q -- '-u critical' "$NOTIFY_LOG"
}

@test "a missing or ambiguous target state stops before the update" {
  uuid=$(add_task 'odd team' linear_issue_id:DEVOPS-1826)
  for states in '[{"id":"s-todo","name":"Todo"}]' '[{"id":"a","name":"Backlog"},{"id":"b","name":"backlog"}]'; do
    : > "$CURL_LOG"
    export STATES="$states"
    run "$script" "$uuid"
    [ "$status" -eq 1 ]
    [[ "$output" == *'no unique Backlog state'* ]]
    [ "$(jq -s 'length' "$CURL_LOG")" = 1 ]
  done
  [ -z "$(tags_of "$uuid")" ]
}

@test "without LINEAR_API_KEY the key comes from pass and never reaches argv or output" {
  unset LINEAR_API_KEY
  uuid=$(add_task 'pass key' linear_issue_id:DEVOPS-1827)
  run "$script" "$uuid"
  [ "$status" -eq 0 ]
  grep -qx 'show work/LINEAR_API_KEY' "$PASS_LOG"
  [ "$(sort -u "$AUTH_LOG")" = 'Authorization: pass-key' ]
  ! grep -q 'pass-key' "$ARGV_LOG"
  [[ "$output" != *pass-key* ]]
}

@test "dispatcher routes key 7 to the toggle and key 0 to the note picker" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.config/taskwarrior-tui/shortcut-scripts"
  printf '#!/usr/bin/env bash\necho "note $*"\n' > "$HOME/.config/taskwarrior-tui/shortcut-scripts/__annotate_with_note.sh"
  chmod +x "$HOME/.config/taskwarrior-tui/shortcut-scripts/__annotate_with_note.sh"
  uuid=$(add_task 'routed' linear_issue_id:DEVOPS-1828)
  export TASKWARRIOR_TUI_REPORT=current
  run "$root/scripts/__tui_shortcut_7.sh" "$uuid"
  [ "$status" -eq 0 ]; [[ "$output" == *'DEVOPS-1828: In Progress -> Backlog'* ]]
  run "$root/scripts/__tui_shortcut_0.sh" "$uuid"
  [ "$status" -eq 0 ]; [ "$output" = "note $uuid" ]
}
