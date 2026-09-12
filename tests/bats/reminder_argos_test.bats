#!/usr/bin/env bats

# The store is the only truth; at and cron are stubs that record what sync
# asked of them. Every test reads the store, the stub logs, or the fire log.

setup() {
  REMINDER="${BATS_TEST_DIRNAME}/../../scripts/__reminder.sh"
  GTK_GUI="${BATS_TEST_DIRNAME}/../../scripts/__reminder_gui.py"
  ARGOS="${BATS_TEST_DIRNAME}/../../.config/argos/reminders.30s.sh"
  BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$BIN"

  export REMINDER_STATE_DIR="${BATS_TEST_TMPDIR}/state"
  export REMINDER_STORE="${REMINDER_STATE_DIR}/reminders.jsonl"
  export REMINDER_LOG="${REMINDER_STATE_DIR}/fire.log"
  export REMINDER_GUI="$BIN/reminder-gui"
  export REMINDER_URL_OPENER="$BIN/url-opener"
  export REMINDER_TASK_OPENER="$BIN/task-opener"
  export REMINDER_MAILER="$BIN/mailer"
  export TEST_MAIL_LOG="${BATS_TEST_TMPDIR}/mail.log"
  printf '#!/usr/bin/env bash\n{ printf "subject: %%s\\n" "$1"; cat; } >>"$TEST_MAIL_LOG"\n' >"$BIN/mailer"
  chmod +x "$BIN/mailer"
  export TEST_TASK_OPENER_LOG="${BATS_TEST_TMPDIR}/task-opener.log"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$1" >"$TEST_TASK_OPENER_LOG"\n' >"$BIN/task-opener"
  chmod +x "$BIN/task-opener"
  export REMINDER_CRON_RUN="/opt/cron/__cron_run.sh"
  export REMINDER_CRON_EVERY="/opt/cron/__cron_every.sh"
  export TEST_ATQ="${BATS_TEST_TMPDIR}/atq"
  export TEST_AT_BODIES="${BATS_TEST_TMPDIR}/at-bodies"
  export TEST_AT_LOG="${BATS_TEST_TMPDIR}/at.log"
  export TEST_ATRM="${BATS_TEST_TMPDIR}/atrm.log"
  export TEST_NEXT_JOB="${BATS_TEST_TMPDIR}/next-job"
  export TEST_CRONTAB="${BATS_TEST_TMPDIR}/crontab"
  export CRON_EVERY_STAMP_DIR="${BATS_TEST_TMPDIR}/cron-every"
  export TEST_OPENER_LOG="${BATS_TEST_TMPDIR}/opener.log"
  export TEST_TASK_LOG="${BATS_TEST_TMPDIR}/task.log"
  export TEST_TASK_STATUS="${BATS_TEST_TMPDIR}/task.status"
  export TEST_ALERT_REQUEST="${BATS_TEST_TMPDIR}/alert.json"
  export PATH="$BIN:$PATH"

  mkdir -p "$REMINDER_STATE_DIR" "$TEST_AT_BODIES"
  : >"$TEST_ATQ"
  : >"$TEST_CRONTAB"
  printf '42\n' >"$TEST_NEXT_JOB"
  printf 'pending\n' >"$TEST_TASK_STATUS"

  # at: `-c N` prints a saved body; anything else queues a job, appends it to
  # the fake atq and records the argv.
  cat >"$BIN/at" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = -c ]; then
  cat "$TEST_AT_BODIES/$2"
  printf '\n'
  exit 0
fi
job_id="$(<"$TEST_NEXT_JOB")"
printf '%s\n' "$((job_id + 1))" >"$TEST_NEXT_JOB"
cat >"$TEST_AT_BODIES/$job_id"
printf '%s\n' "$*" >>"$TEST_AT_LOG"
stamp="${*: -1}"
when="${stamp:0:4}-${stamp:4:2}-${stamp:6:2} ${stamp:8:2}:${stamp:10:2}"
printf '%s %s r decoder\n' "$job_id" "$(date -d "$when" '+%a %b %-d %H:%M:%S %Y')" >>"$TEST_ATQ"
printf 'warning: commands will be executed using /bin/sh\n' >&2
printf 'job %s at %s\n' "$job_id" "$(date -d "$when")" >&2
STUB

  cat >"$BIN/atq" <<'STUB'
#!/usr/bin/env bash
cat "$TEST_ATQ"
STUB

  cat >"$BIN/atrm" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_ATRM"
grep -v "^$1 " "$TEST_ATQ" >"$TEST_ATQ.tmp" || true
mv "$TEST_ATQ.tmp" "$TEST_ATQ"
STUB

  cat >"$BIN/crontab" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  -l) cat "$TEST_CRONTAB" ;;
  -) cat >"$TEST_CRONTAB" ;;
esac
STUB

  cat >"$BIN/task" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_TASK_LOG"
for arg in "$@"; do
  case "$arg" in
    *.uuid) printf '%s\n' "${arg%.uuid}"; exit 0 ;;
    *.status) cat "$TEST_TASK_STATUS"; exit 0 ;;
    *.description) printf 'review the lease-to-own offer\n'; exit 0 ;;
  esac
done
STUB

  cat >"$BIN/url-opener" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_OPENER_LOG"
STUB

  chmod +x "$BIN"/*
}

gui_returns() {
  cat >"$REMINDER_GUI" <<STUB
#!/usr/bin/env bash
cat >"\$TEST_ALERT_REQUEST"
printf '%s\n' '$1'
STUB
  chmod +x "$REMINDER_GUI"
}

gui_closes() {
  cat >"$REMINDER_GUI" <<'STUB'
#!/usr/bin/env bash
cat >"$TEST_ALERT_REQUEST"
exit 1
STUB
  chmod +x "$REMINDER_GUI"
}

last_record() {
  jq -c -s 'reduce .[] as $r ({}; .[$r.id] = $r) | .[]' "$REMINDER_STORE" | tail -n1
}

only_id() {
  last_record | jq -r '.id'
}

@test "add writes a record and queues an at job carrying only the id" {
  run "$REMINDER" add "Don't blink" '2026-09-10 09:30'

  [ "$status" -eq 0 ]
  id="$(only_id)"
  [[ "$id" =~ ^[0-9a-f]{8}$ ]]
  [ "$(last_record | jq -r '.label')" = "Don't blink" ]
  [ "$(last_record | jq -r '.when')" = "2026-09-10T09:30:00$(date -d 2026-09-10 +%:z)" ]
  [ "$(last_record | jq -r '.status')" = active ]
  [ "$(<"$TEST_AT_LOG")" = "-q r -t 202609100930" ]
  [[ "$(<"$TEST_AT_BODIES/42")" == *" fire $id" ]]
  [[ "$(<"$TEST_AT_BODIES/42")" != *"blink"* ]]
  [[ "$output" == "Added $id: Don't blink at Thu 10 Sep 09:30" ]]
}

@test "date-first specs parse to an exact timestamp" {
  run "$REMINDER" add "Standup" 'Tuesday 16:20'

  [ "$status" -eq 0 ]
  expected="$(date -d 'Tuesday 16:20' +%Y%m%d%H%M)"
  [ "$(<"$TEST_AT_LOG")" = "-q r -t $expected" ]
}

@test "a subject becomes typed and a task subject resolves to its uuid" {
  run "$REMINDER" add "Lease" 1h --subject task:f5b77f7b
  [ "$status" -eq 0 ]
  [ "$(last_record | jq -r '.subject')" = "task:f5b77f7b" ]

  run "$REMINDER" add "Read" 1h --subject 'see https://example.com/a'
  [ "$status" -eq 0 ]
  [ "$(last_record | jq -r '.subject')" = "text:see https://example.com/a" ]
}

@test "a repeat writes a managed crontab block wrapped by __cron_run" {
  printf '0 5 * * 1 /usr/bin/backup\n' >"$TEST_CRONTAB"

  run "$REMINDER" add "Weekly review" --repeat '0 9 * * 1'

  [ "$status" -eq 0 ]
  id="$(only_id)"
  [ "$(last_record | jq -r '.repeat')" = "0 9 * * 1" ]
  [ ! -s "$TEST_AT_LOG" ]
  grep -q '^0 5 \* \* 1 /usr/bin/backup$' "$TEST_CRONTAB"
  grep -q '^# BEGIN remind' "$TEST_CRONTAB"
  grep -q "^0 9 \* \* 1 /opt/cron/__cron_run.sh remind-$id -- .*__reminder.sh fire $id$" "$TEST_CRONTAB"
  grep -q "^@reboot sleep 90 && .*__reminder.sh sync$" "$TEST_CRONTAB"
  grep -q '^# END remind$' "$TEST_CRONTAB"
  ! grep -q 'Weekly review' "$TEST_CRONTAB"
}

@test "an interval repeat goes through __cron_every for catch-up" {
  run "$REMINDER" add "Check seats" --repeat 'every 7d'

  [ "$status" -eq 0 ]
  id="$(only_id)"
  grep -q "^\*/15 \* \* \* \* /opt/cron/__cron_every.sh remind-$id 604800 -- /opt/cron/__cron_run.sh remind-$id -- .*fire $id$" "$TEST_CRONTAB"
}

@test "sync removes stale at jobs and creates missing ones without touching foreign lines" {
  "$REMINDER" add "Keep me" '2026-09-10 09:30' >/dev/null
  id="$(only_id)"
  printf '7 Mon Aug 17 09:00:00 2026 r decoder\n' >>"$TEST_ATQ"
  printf '/x/__reminder.sh fire deadbeef\n' >"$TEST_AT_BODIES/7"
  : >"$TEST_AT_LOG"

  run "$REMINDER" sync
  [ "$status" -eq 0 ]
  [ "$(<"$TEST_ATRM")" = "7" ]
  [ ! -s "$TEST_AT_LOG" ]

  : >"$TEST_ATQ"
  run "$REMINDER" sync
  [ "$status" -eq 0 ]
  [ "$(<"$TEST_AT_LOG")" = "-q r -t 202609100930" ]
  [[ "$(<"$TEST_AT_BODIES/43")" == *" fire $id" ]]
}

@test "delete marks the record and drops its at job" {
  "$REMINDER" add "Gone soon" '2026-09-10 09:30' >/dev/null
  id="$(only_id)"

  run "$REMINDER" delete "$id"

  [ "$status" -eq 0 ]
  [ "$(last_record | jq -r '.status')" = deleted ]
  [ "$(<"$TEST_ATRM")" = "42" ]
  [ "$("$REMINDER" list --json | jq length)" -eq 0 ]
}

@test "list --json reports the last record per id with a title and url" {
  "$REMINDER" add "Old label" "$(date -d '+1 day' '+%Y-%m-%d 09:30')" --subject 'link: https://vodafone.de/kontakt' >/dev/null
  id="$(only_id)"
  "$REMINDER" edit "$id" --label "New label" >/dev/null

  run "$REMINDER" list --json

  [ "$status" -eq 0 ]
  [ "$(jq length <<<"$output")" -eq 1 ]
  [ "$(jq -r '.[0].label' <<<"$output")" = "New label" ]
  [ "$(jq -r '.[0].title' <<<"$output")" = "New label" ]
  [ "$(jq -r '.[0].url' <<<"$output")" = "https://vodafone.de/kontakt" ]
  [ "$(jq -r '.[0].overdue' <<<"$output")" = false ]
}

@test "fire shows the resolved subject and done spends the one-shot" {
  "$REMINDER" add "Call vodafone" '2026-09-08 09:00' --subject 'link: https://vodafone.de/kontakt' >/dev/null
  id="$(only_id)"
  gui_returns '{"action":"done"}'

  run "$REMINDER" fire "$id"

  [ "$status" -eq 0 ]
  [ "$(jq -r '.title' "$TEST_ALERT_REQUEST")" = "Call vodafone" ]
  [ "$(jq -r '.url' "$TEST_ALERT_REQUEST")" = "https://vodafone.de/kontakt" ]
  [ "$(jq -r '.due' "$TEST_ALERT_REQUEST")" = "Tue 08 Sep 09:00" ]
  [ "$(last_record | jq -r '.status')" = done ]
  [ "$(last_record | jq -r '.when // "none"')" = none ]
  [ -n "$(last_record | jq -r '.last_fired')" ]
  grep -q "	$id	fired	show due 2026-09-08T09:00:00.* late .*	Call vodafone$" "$REMINDER_LOG"
  grep -q "	$id	done	done	Call vodafone$" "$REMINDER_LOG"
}

@test "snooze is an edit of when plus sync" {
  "$REMINDER" add "Snooze me" '2026-09-08 09:00' >/dev/null
  id="$(only_id)"
  gui_returns '{"action":"snooze","when":"2026-09-10 09:30"}'

  run "$REMINDER" fire "$id"

  [ "$status" -eq 0 ]
  [ "$(last_record | jq -r '.status')" = active ]
  [ "$(last_record | jq -r '.when')" = "2026-09-10T09:30:00$(date -d 2026-09-10 +%:z)" ]
  tail -n1 "$TEST_AT_LOG" | grep -q -- '-q r -t 202609100930'
  grep -q "	$id	snoozed	2026-09-10T09:30" "$REMINDER_LOG"
}

@test "a closed dialog snoozes by default instead of dropping the reminder" {
  "$REMINDER" add "Do not lose me" '2026-09-08 09:00' >/dev/null
  id="$(only_id)"
  gui_closes

  run env REMINDER_DEFAULT_SNOOZE='2026-09-10 09:30' "$REMINDER" fire "$id"

  [ "$status" -eq 0 ]
  [ "$(last_record | jq -r '.status')" = active ]
  [ "$(last_record | jq -r '.when')" = "2026-09-10T09:30:00$(date -d 2026-09-10 +%:z)" ]
  tail -n1 "$TEST_AT_LOG" | grep -q -- '-q r -t 202609100930'
  grep -q "	$id	dismissed	snooze" "$REMINDER_LOG"
}

@test "a re-fire while the dialog is still open refreshes the snooze instead of opening a second dialog" {
  "$REMINDER" add "Away from desk" '2026-09-08 09:00' >/dev/null
  id="$(only_id)"
  cat >"$REMINDER_GUI" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null
printf '.\n' >>"$TEST_ALERT_REQUEST.count"
sleep 2
printf '{"action":"done"}\n'
STUB
  chmod +x "$REMINDER_GUI"

  "$REMINDER" fire "$id" &
  first=$!
  sleep 0.5
  run "$REMINDER" fire "$id"
  [ "$status" -eq 0 ]
  wait "$first"

  [ "$(wc -l <"$TEST_ALERT_REQUEST.count")" -eq 1 ]
  grep -q "	$id	skipped	dialog already open, snoozed to " "$REMINDER_LOG"
  grep -q "	$id	done	done	Away from desk$" "$REMINDER_LOG"
  [ "$(last_record | jq -r '.status')" = done ]
  [ "$(last_record | jq -r '.when // "none"')" = none ]
}

@test "task done from the dialog completes the task by uuid" {
  "$REMINDER" add "" 1h --subject task:f5b77f7b-29ba-4167-a161-71d35b73b807 >/dev/null
  id="$(only_id)"
  gui_returns '{"action":"done"}'

  run "$REMINDER" fire "$id"

  [ "$status" -eq 0 ]
  [ "$(jq -r '.title' "$TEST_ALERT_REQUEST")" = "review the lease-to-own offer" ]
  [ "$(jq -r '.subject_type' "$TEST_ALERT_REQUEST")" = task ]
  grep -q 'f5b77f7b-29ba-4167-a161-71d35b73b807 done' "$TEST_TASK_LOG"
  [ "$(last_record | jq -r '.status')" = done ]
}

@test "a reminder whose task is completed is skipped, not shown" {
  "$REMINDER" add "Stale" 1h --subject task:f5b77f7b >/dev/null
  id="$(only_id)"
  printf 'completed\n' >"$TEST_TASK_STATUS"
  gui_returns '{"action":"done"}'

  run "$REMINDER" fire "$id"

  [ "$status" -eq 0 ]
  [ ! -f "$TEST_ALERT_REQUEST" ]
  [ "$(last_record | jq -r '.status')" = done ]
  grep -q "	$id	skipped	task completed	Stale$" "$REMINDER_LOG"
}

@test "done on a repeat keeps the schedule and clears only the pending one-shot" {
  "$REMINDER" add "Weekly" 1h --repeat '0 9 * * 1' >/dev/null
  id="$(only_id)"
  gui_returns '{"action":"done"}'

  run "$REMINDER" fire "$id"

  [ "$status" -eq 0 ]
  [ "$(last_record | jq -r '.status')" = active ]
  [ "$(last_record | jq -r '.when // "none"')" = none ]
  [ "$(last_record | jq -r '.repeat')" = "0 9 * * 1" ]
  grep -q "remind-$id" "$TEST_CRONTAB"
}

@test "the open action opens the url without a dialog and logs it" {
  gui_returns '{"action":"done"}'
  "$REMINDER" add "Standup doc" 1h --subject url:https://example.com/standup --action open >/dev/null
  id="$(only_id)"

  run "$REMINDER" fire "$id"

  [ "$status" -eq 0 ]
  [ ! -f "$TEST_ALERT_REQUEST" ]
  [ "$(<"$TEST_OPENER_LOG")" = "https://example.com/standup" ]
  [ "$(last_record | jq -r '.status')" = done ]
  grep -q "	$id	opened	https://example.com/standup	Standup doc$" "$REMINDER_LOG"
}

@test "the exec action runs the literal command and records its exit code" {
  "$REMINDER" add "Touch marker" 1h --action exec --command "touch '$BATS_TEST_TMPDIR/marker'" >/dev/null
  id="$(only_id)"

  run "$REMINDER" fire "$id"

  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/marker" ]
  grep -q "	$id	exec	rc=0	Touch marker$" "$REMINDER_LOG"
}

@test "firing an unknown or inactive id leaves one log line and no dialog" {
  gui_returns '{"action":"done"}'
  run "$REMINDER" fire deadbeef
  [ "$status" -eq 0 ]
  grep -q "	deadbeef	missing	" "$REMINDER_LOG"

  "$REMINDER" add "Deleted" 1h >/dev/null
  id="$(only_id)"
  "$REMINDER" delete "$id" >/dev/null
  run "$REMINDER" fire "$id"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_ALERT_REQUEST" ]
  grep -q "	$id	skipped	status deleted	Deleted$" "$REMINDER_LOG"
}

@test "gc keeps only the last active record per id" {
  "$REMINDER" add "Keep" 1h >/dev/null
  keep="$(only_id)"
  "$REMINDER" edit "$keep" --label "Keep edited" >/dev/null
  "$REMINDER" add "Drop" 1h >/dev/null
  "$REMINDER" delete "$(only_id)" >/dev/null
  [ "$(wc -l <"$REMINDER_STORE")" -eq 4 ]

  run "$REMINDER" gc

  [ "$status" -eq 0 ]
  [ "$(wc -l <"$REMINDER_STORE")" -eq 1 ]
  [ "$(jq -r '.id' "$REMINDER_STORE")" = "$keep" ]
  [ "$(jq -r '.label' "$REMINDER_STORE")" = "Keep edited" ]
}

@test "open prefers a labelled link over a bare url" {
  "$REMINDER" add "Call" 1h --subject 'context https://example.com/other
link: https://vodafone.de/kontakt' >/dev/null

  run "$REMINDER" open "$(only_id)"

  [ "$status" -eq 0 ]
  [ "$(<"$TEST_OPENER_LOG")" = "https://vodafone.de/kontakt" ]
}

@test "open on a reminder with no url reports instead of opening" {
  "$REMINDER" add "Plain" 1h --subject 'just some context' >/dev/null
  gui_returns '{"closed":true}'

  run "$REMINDER" open "$(only_id)"

  [ "$status" -ne 0 ]
  [ ! -s "$TEST_OPENER_LOG" ]
}

@test "a schedule at rejects fails loudly and leaves the record for the next sync" {
  cat >"$BIN/at" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null
printf 'Garbled time\n' >&2
exit 1
STUB
  chmod +x "$BIN/at"

  run "$REMINDER" add "Broken" '2026-09-10 09:30'

  [ "$status" -eq 1 ]
  [[ "$output" == *"at rejected"* ]]
  [[ "$output" == *"Garbled time"* ]]
  [ "$(last_record | jq -r '.label')" = "Broken" ]
}

@test "a time in the off window warns" {
  run "$REMINDER" add "Night" '2026-09-10 03:00'
  [ "$status" -eq 0 ]
  [[ "$output" == *"off window"* ]]

  run "$REMINDER" add "Night cron" --repeat '0 4 * * *'
  [ "$status" -eq 0 ]
  [[ "$output" == *"never fires there"* ]]
}

@test "the GTK add form feeds add and the edit form only sends changed fields" {
  cat >"$REMINDER_GUI" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null
printf '{"label":"Stand up","when":"2026-09-10 09:30","repeat":"","subject":""}\n'
STUB
  chmod +x "$REMINDER_GUI"
  run "$REMINDER" add-dialog
  [ "$status" -eq 0 ]
  id="$(only_id)"
  [ "$(last_record | jq -r '.label')" = "Stand up" ]
  [ "$(last_record | jq -r '.origin')" = dialog ]

  cat >"$REMINDER_GUI" <<'STUB'
#!/usr/bin/env bash
request="$(cat)"
jq -c '.label = "Stand up, edited"' <<<"$request"
STUB
  run "$REMINDER" edit-dialog "$id"
  [ "$status" -eq 0 ]
  [ "$(last_record | jq -r '.label')" = "Stand up, edited" ]
  [ "$(last_record | jq -r '.when')" = "2026-09-10T09:30:00$(date -d 2026-09-10 +%:z)" ]
  [ "$(grep -c -- '-t 202609100930' "$TEST_AT_LOG")" -eq 1 ]
}

@test "the GTK reminder UI passes its dependency check" {
  run "$GTK_GUI" --check

  [ "$status" -eq 0 ]
  [ "$output" = "GTK 3 ready; position=center-always" ]
}

@test "edit with no options opens the record as a form and applies what changed" {
  "$REMINDER" add "pto off" '2026-09-27 22:00' --action exec --command '/x/__toggles.sh __run pto-mode off' >/dev/null
  id="$(only_id)"
  cat >"$BIN/form-editor" <<'STUB'
#!/usr/bin/env bash
cp "$1" "$TEST_FORM_SEEN"
sed -i -e 's#/x/#/y/#' -e 's/^when: .*/when: 2026-09-27 21:30/' "$1"
STUB
  chmod +x "$BIN/form-editor"
  export TEST_FORM_SEEN="${BATS_TEST_TMPDIR}/form"

  run env XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR" REMINDER_EDITOR="$BIN/form-editor" "$REMINDER" edit "$id"

  [ "$status" -eq 0 ]
  [ "$output" = "Updated $id" ]
  grep -q "^# pto off  \[$id\]" "$TEST_FORM_SEEN"
  grep -q '^when: 2026-09-27 22:00$' "$TEST_FORM_SEEN"
  grep -q '^action: exec$' "$TEST_FORM_SEEN"
  grep -q '^command: /x/__toggles.sh __run pto-mode off$' "$TEST_FORM_SEEN"
  [ "$(last_record | jq -r '.command')" = "/y/__toggles.sh __run pto-mode off" ]
  [ "$(last_record | jq -r '.when')" = "2026-09-27T21:30:00$(date -d 2026-09-27 +%:z)" ]
  tail -n1 "$TEST_AT_LOG" | grep -q -- '-q r -t 202609272130'
  ! ls "$BATS_TEST_TMPDIR"/remind-edit.* >/dev/null 2>&1
}

@test "an untouched form changes nothing and an aborted editor leaves the record alone" {
  "$REMINDER" add "Keep me" '2026-09-27 22:00' >/dev/null
  id="$(only_id)"
  before="$(wc -l <"$REMINDER_STORE")"

  run env XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR" REMINDER_EDITOR=true "$REMINDER" edit "$id"
  [ "$status" -eq 0 ]
  [ "$output" = "Unchanged $id" ]
  [ "$(wc -l <"$REMINDER_STORE")" -eq "$before" ]

  run env XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR" REMINDER_EDITOR=false "$REMINDER" edit "$id"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing changed"* ]]
  [ "$(wc -l <"$REMINDER_STORE")" -eq "$before" ]
  ! ls "$BATS_TEST_TMPDIR"/remind-edit.* >/dev/null 2>&1
}

@test "the form refuses exec without a command and can switch an exec back to show" {
  "$REMINDER" add "pto off" '2026-09-27 22:00' --action exec --command '/x/y' >/dev/null
  id="$(only_id)"
  printf '#!/usr/bin/env bash\nsed -i "s#^command:.*#command:#" "$1"\n' >"$BIN/clear-command"
  printf '#!/usr/bin/env bash\nsed -i -e "s/^action:.*/action: show/" -e "s#^command:.*#command:#" "$1"\n' >"$BIN/to-show"
  chmod +x "$BIN/clear-command" "$BIN/to-show"

  run env REMINDER_EDITOR="$BIN/clear-command" "$REMINDER" edit "$id"
  [ "$status" -eq 1 ]
  [[ "$output" == *"exec action needs a command"* ]]
  [ "$(last_record | jq -r '.command')" = "/x/y" ]

  run env REMINDER_EDITOR="$BIN/to-show" "$REMINDER" edit "$id"
  [ "$status" -eq 0 ]
  [ "$(last_record | jq -r '.action')" = show ]
  [ "$(last_record | jq -r '.command // "gone"')" = gone ]
}

@test "the Argos applet shows the count, the overdue count, and opens the agenda" {
  cat >"$BIN/reminder-helper" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = list ]; then
  cat <<'JSON'
[
 {"id":"0a1b2c3d","label":"Plan | <review>","when":"2026-09-10T09:30:00+02:00","action":"show","status":"active","title":"Plan | <review>","url":"https://vodafone.de/kontakt","subject":"text:link: https://vodafone.de/kontakt","overdue":true},
 {"id":"deadbeef","label":"Weekly","repeat":"0 9 * * 1","action":"show","status":"active","title":"Weekly","url":"","overdue":false},
 {"id":"e8ec0000","label":"pto off","when":"2026-09-27T22:00:00+02:00","action":"exec","command":"/x/__toggles.sh __run pto-mode off","status":"active","title":"pto off","url":"","overdue":false}
]
JSON
fi
STUB
  chmod +x "$BIN/reminder-helper"

  run env REMINDER_HELPER="$BIN/reminder-helper" "$ARGOS"

  [ "$status" -eq 0 ]
  [[ "$output" == *"color='#ff9944'>3</span>"* ]]
  [[ "$output" == *"1 overdue | color=#ff9944"* ]]
  [[ "$output" == *"Open agenda | bash='/usr/local/bin/tmux new-window -n reminders \"$BIN/reminder-helper\" agenda'"* ]]
  [[ "$output" == *"add-dialog"* ]]
  [[ "$output" != *"Plan"* ]]
  [[ "$output" != *"vodafone"* ]]
  [[ "$output" != *"__toggles"* ]]
}

@test "an exec repeat is silent on 0, retires itself on a 2 hit, and survives an error" {
  "$REMINDER" add "Seats check" --repeat 'every 7d' --action exec --command "cat $BATS_TEST_TMPDIR/verdict; exit \$(cat $BATS_TEST_TMPDIR/rc)" >/dev/null
  id="$(only_id)"
  gui_returns '{"action":"dismiss"}'

  printf 'nothing yet\n' >"$BATS_TEST_TMPDIR/verdict"; printf '0\n' >"$BATS_TEST_TMPDIR/rc"
  run "$REMINDER" fire "$id"
  [ "$status" -eq 0 ]
  [ "$(last_record | jq -r '.status')" = active ]
  [ ! -s "$TEST_ALERT_REQUEST" ]
  grep -q "	$id	exec	rc=0	" "$REMINDER_LOG"

  printf 'broken pipe\n' >"$BATS_TEST_TMPDIR/verdict"; printf '1\n' >"$BATS_TEST_TMPDIR/rc"
  run "$REMINDER" fire "$id"
  [ "$status" -eq 0 ]
  [ "$(last_record | jq -r '.status')" = active ]
  [ "$(last_record | jq -r '.repeat')" = "every 7d" ]
  [ "$(jq -r '.body' "$TEST_ALERT_REQUEST")" = $'exit 1\nbroken pipe' ]
  # dismissed: the provisional snooze stands, so this run comes back
  [ -n "$(last_record | jq -r '.when // ""')" ]

  printf 'seats: 3 available\n' >"$BATS_TEST_TMPDIR/verdict"; printf '2\n' >"$BATS_TEST_TMPDIR/rc"
  : >"$TEST_ALERT_REQUEST"
  gui_returns '{"action":"done"}'
  run "$REMINDER" fire "$id"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.body' "$TEST_ALERT_REQUEST")" = "seats: 3 available" ]
  [ "$(jq -r '.title' "$TEST_ALERT_REQUEST")" = "Seats check" ]
  [ "$(last_record | jq -r '.status')" = done ]
  [ "$(last_record | jq -r '.repeat // "gone"')" = gone ]
  ! grep -q "remind-$id" "$TEST_CRONTAB"
}

@test "notify mail: a hit is mailed and the reminder is done without a dialog" {
  "$REMINDER" add "tmux watch" --repeat '26 10 * * 1' --action exec --command "echo 'tmux 3.8 released'; exit 2" --notify mail >/dev/null
  id="$(only_id)"
  gui_returns '{"action":"dismiss"}'

  run "$REMINDER" fire "$id"

  [ "$status" -eq 0 ]
  [ ! -s "$TEST_ALERT_REQUEST" ]
  grep -q '^subject: tmux watch$' "$TEST_MAIL_LOG"
  grep -q '^tmux 3.8 released$' "$TEST_MAIL_LOG"
  [ "$(last_record | jq -r '.status')" = done ]
  ! grep -q "remind-$id" "$TEST_CRONTAB"
}

@test "notify silent: the command told you itself, the hit just retires the reminder" {
  "$REMINDER" add "self-mailing watch" --repeat '26 10 * * 1' --action exec --command "exit 2" --notify silent >/dev/null
  id="$(only_id)"
  gui_returns '{"action":"dismiss"}'

  run "$REMINDER" fire "$id"

  [ "$status" -eq 0 ]
  [ ! -s "$TEST_ALERT_REQUEST" ]
  [ ! -f "$TEST_MAIL_LOG" ]
  [ "$(last_record | jq -r '.status')" = done ]
}

@test "notify mail on a show reminder mails the body on the date" {
  "$REMINDER" add "Renew the domain" '2026-09-27 09:00' --subject 'url:https://example.com/renew' --notify mail >/dev/null
  id="$(only_id)"

  run "$REMINDER" fire "$id"

  [ "$status" -eq 0 ]
  grep -q '^subject: Renew the domain$' "$TEST_MAIL_LOG"
  grep -q 'https://example.com/renew' "$TEST_MAIL_LOG"
  [ "$(last_record | jq -r '.status')" = done ]
  grep -q "	$id	mailed	" "$REMINDER_LOG"
}

@test "the agenda renders and applies :notify:" {
  "$REMINDER" add "tmux watch" --repeat '26 10 * * 1' --action exec --command "/x/watch.sh" --notify silent >/dev/null
  id="$(only_id)"
  run "$REMINDER" agenda render
  [[ "$output" == *"   :notify: silent"* ]]

  agenda="${BATS_TEST_TMPDIR}/agenda.org"
  "$REMINDER" agenda render | sed 's/^   :notify: silent$/   :notify: mail/' >"$agenda"
  run "$REMINDER" agenda apply "$agenda"
  [ "$status" -eq 0 ]
  [ "$(last_record | jq -r '.notify')" = mail ]

  "$REMINDER" agenda render | sed '/^   :notify:/d' >"$agenda"
  run "$REMINDER" agenda apply "$agenda"
  [ "$(last_record | jq -r '.notify // "dialog"')" = dialog ]
}

@test "on-hit and on-miss run the branch with the check output on stdin, and chain" {
  "$REMINDER" add "revert check" --repeat 'every 1d' --action exec \
    --command "cat $BATS_TEST_TMPDIR/verdict; exit \$(cat $BATS_TEST_TMPDIR/rc)" \
    --on-hit "cat >$BATS_TEST_TMPDIR/hit && $BIN/mailer 'reverted'" \
    --on-miss "cat >$BATS_TEST_TMPDIR/miss" --notify silent >/dev/null
  id="$(only_id)"

  printf 'still there\n' >"$BATS_TEST_TMPDIR/verdict"; printf '0\n' >"$BATS_TEST_TMPDIR/rc"
  run "$REMINDER" fire "$id"
  [ "$status" -eq 0 ]
  [ "$(<"$BATS_TEST_TMPDIR/miss")" = "still there" ]
  [ ! -f "$BATS_TEST_TMPDIR/hit" ]
  [ "$(last_record | jq -r '.status')" = active ]
  grep -q "	$id	on_miss	rc=0	" "$REMINDER_LOG"

  printf 'gone\n' >"$BATS_TEST_TMPDIR/verdict"; printf '2\n' >"$BATS_TEST_TMPDIR/rc"
  run "$REMINDER" fire "$id"
  [ "$status" -eq 0 ]
  [ "$(<"$BATS_TEST_TMPDIR/hit")" = "gone" ]
  grep -q '^subject: reverted$' "$TEST_MAIL_LOG"
  [ "$(last_record | jq -r '.status')" = done ]
  grep -q "	$id	on_hit	rc=0	" "$REMINDER_LOG"

  run "$REMINDER" agenda render
  [[ "$output" != *"revert check"* ]]
}

@test "a failing on-hit keeps a repeating reminder alive and reports the hook, not a hit" {
  "$REMINDER" add "download on release" --repeat 'every 1d' --action exec \
    --command "echo 3.8 is out; exit 2" \
    --on-hit "echo no space left; exit 1" --notify mail >/dev/null
  id="$(only_id)"

  run "$REMINDER" fire "$id"
  [ "$status" -eq 0 ]
  grep -q "	$id	on_hit	rc=1	" "$REMINDER_LOG"
  grep -q '^subject: error: download on release$' "$TEST_MAIL_LOG"
  grep -q '^on-hit exit 1$' "$TEST_MAIL_LOG"
  grep -q '^no space left$' "$TEST_MAIL_LOG"
  grep -q '^3.8 is out$' "$TEST_MAIL_LOG"
  ! grep -q '^subject: download on release$' "$TEST_MAIL_LOG"
  [ "$(last_record | jq -r '.status')" = active ]
  [ "$(last_record | jq -r '.repeat')" = "every 1d" ]
  run "$REMINDER" agenda render
  [[ "$output" == *"download on release"* ]]
}

@test "the agenda round-trips :on-hit: and :on-miss:" {
  "$REMINDER" add "watch" --repeat 'every 1d' --action exec --command /x/check.sh --on-hit '/x/y.sh && /x/mail.sh "yes"' >/dev/null
  id="$(only_id)"
  run "$REMINDER" agenda render
  [[ "$output" == *'   :on-hit: /x/y.sh && /x/mail.sh "yes"'* ]]
  agenda="${BATS_TEST_TMPDIR}/agenda.org"
  "$REMINDER" agenda render | sed "s|^   :id: $id\$|   :on-miss: /x/mail.sh \"not yet\"\n   :id: $id|" >"$agenda"
  run "$REMINDER" agenda apply "$agenda"
  [ "$status" -eq 0 ]
  [ "$(last_record | jq -r '.on_miss')" = '/x/mail.sh "not yet"' ]
  [ "$(last_record | jq -r '.on_hit')" = '/x/y.sh && /x/mail.sh "yes"' ]
}

@test "a hit on an exec repeat that is snoozed keeps a one-shot and no schedule" {
  "$REMINDER" add "Seats check" --repeat 'every 7d' --action exec --command "echo found; exit 2" >/dev/null
  id="$(only_id)"
  gui_returns '{"action":"snooze","when":"2026-09-12 09:00"}'

  run "$REMINDER" fire "$id"

  [ "$status" -eq 0 ]
  [ "$(last_record | jq -r '.status')" = active ]
  [ "$(last_record | jq -r '.repeat // "gone"')" = gone ]
  [ "$(last_record | jq -r '.when')" = "2026-09-12T09:00:00$(date -d 2026-09-12 +%:z)" ]
  ! grep -q "remind-$id" "$TEST_CRONTAB"
  tail -n1 "$TEST_AT_LOG" | grep -q -- '-q r -t 202609120900'
}

@test "the dialog's Open task on a task reminder opens the task, not a link" {
  "$REMINDER" add "Review it" '2026-09-27 22:00' --subject task:abcdef12-0000-0000-0000-000000000000 >/dev/null
  id="$(only_id)"
  printf 'pending\n' >"$TEST_TASK_STATUS"
  # open re-shows the dialog, so the stub answers open once, then closes
  cat >"$REMINDER_GUI" <<STUB
#!/usr/bin/env bash
cat >"\$TEST_ALERT_REQUEST"
if [ -f "$BATS_TEST_TMPDIR/opened-once" ]; then echo '{"closed":true}'; else touch "$BATS_TEST_TMPDIR/opened-once"; echo '{"action":"open"}'; fi
STUB
  chmod +x "$REMINDER_GUI"

  run "$REMINDER" fire "$id"

  [ "$status" -eq 0 ]
  [ "$(jq -r '.subject_type' "$TEST_ALERT_REQUEST")" = task ]
  [ "$(<"$TEST_TASK_OPENER_LOG")" = "task:abcdef12-0000-0000-0000-000000000000" ]
  [ ! -s "$TEST_OPENER_LOG" ]
}

@test "sync drops the cron-every stamp of a retired interval repeat and keeps live ones" {
  "$REMINDER" add "Weekly" --repeat 'every 7d' >/dev/null
  live="$(only_id)"
  mkdir -p "$CRON_EVERY_STAMP_DIR"
  printf '1789000000\n' >"$CRON_EVERY_STAMP_DIR/remind-$live"
  printf '1789000000\n' >"$CRON_EVERY_STAMP_DIR/remind-deadbeef"
  printf '1789000000\n' >"$CRON_EVERY_STAMP_DIR/r2r-session-sync-full"

  run "$REMINDER" sync

  [ "$status" -eq 0 ]
  [[ "$output" == *"stamp: dropped remind-deadbeef"* ]]
  [ -f "$CRON_EVERY_STAMP_DIR/remind-$live" ]
  [ ! -f "$CRON_EVERY_STAMP_DIR/remind-deadbeef" ]
  [ -f "$CRON_EVERY_STAMP_DIR/r2r-session-sync-full" ]

  "$REMINDER" delete "$live" >/dev/null
  [ ! -f "$CRON_EVERY_STAMP_DIR/remind-$live" ]
}

@test "agenda render groups by horizon with org timestamps and detail lines" {
  "$REMINDER" add "pto off" '2026-09-27 22:00' --action exec --command '/x/__toggles.sh __run pto-mode off' >/dev/null
  "$REMINDER" add "Weekly" --repeat '0 9 * * 1' --subject 'text:first line
second line' >/dev/null
  "$REMINDER" add "Soon" "$(date -d '+2 hours' '+%Y-%m-%d %H:%M')" >/dev/null
  "$REMINDER" add "Gone" '2020-01-01 09:00' >/dev/null

  run "$REMINDER" agenda render

  [ "$status" -eq 0 ]
  [[ "$output" == *"* Overdue"* ]]
  [[ "$output" == *"* Today"* ]]
  [[ "$output" == *"* Later"* ]]
  [[ "$output" == *"* Recurring"* ]]
  [[ "$output" == *"** <2026-09-27 Sun 22:00> pto off"* ]]
  [[ "$output" == *"   :action: exec"* ]]
  [[ "$output" == *"   :runs: /x/__toggles.sh __run pto-mode off"* ]]
  [[ "$output" == *"** <0 9 * * 1> Weekly"* ]]
  [[ "$output" == *"   :notes: first line"* ]]
  [[ "$output" != *":subject:"* ]]
  [[ "$output" != *"second line"* ]]
  [[ "$output" != *"subject: null"* ]]
  [[ "$output" != *":action: show"* ]]
  [[ "$output" == *"   :id: "* ]]
  # sections come in horizon order
  overdue_at="$(grep -n '^\* Overdue' <<<"$output" | cut -d: -f1)"
  later_at="$(grep -n '^\* Later' <<<"$output" | cut -d: -f1)"
  recurring_at="$(grep -n '^\* Recurring' <<<"$output" | cut -d: -f1)"
  [ "$overdue_at" -lt "$later_at" ]
  [ "$later_at" -lt "$recurring_at" ]
}

@test "agenda apply edits changed lines, deletes removed ones, and adds id-less ones" {
  "$REMINDER" add "pto off" '2026-09-27 22:00' --action exec --command '/x/__toggles.sh __run pto-mode off' >/dev/null
  pto="$(only_id)"
  "$REMINDER" add "Drop me" '2026-09-28 09:00' >/dev/null
  "$REMINDER" add "Weekly" --repeat '0 9 * * 1' >/dev/null
  weekly="$(jq -r 'select(.label == "Weekly") | .id' "$REMINDER_STORE")"
  drop="$(jq -r 'select(.label == "Drop me") | .id' "$REMINDER_STORE")"
  agenda="${BATS_TEST_TMPDIR}/agenda.org"
  cat >"$agenda" <<EOF
#+TITLE: Reminders
# comment
* Later

** <2026-09-27 Sun 21:30> pto off, renamed
   :action: exec
   :runs: /y/__toggles.sh __run pto-mode off
   :id: $pto

* Recurring

** <0 9 * * 1> Weekly
   :id: $weekly

** <2026-10-01 Thu 10:00> Dentist

** <every 7d> Read the newsletter
   :action: open
   :url: https://example.com/news
EOF

  run "$REMINDER" agenda apply "$agenda"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Updated $pto"* ]]
  [[ "$output" == *"Unchanged $weekly"* ]]
  [[ "$output" == *"Deleted $drop"* ]]
  [[ "$output" == *"Added "*"Dentist"* ]]
  rec="$(jq -c -s 'reduce .[] as $r ({}; .[$r.id] = $r) | .[]' "$REMINDER_STORE")"
  [ "$(jq -r --arg id "$pto" 'select(.id == $id) | .label' <<<"$rec")" = "pto off, renamed" ]
  [ "$(jq -r --arg id "$pto" 'select(.id == $id) | .when' <<<"$rec")" = "2026-09-27T21:30:00$(date -d 2026-09-27 +%:z)" ]
  [ "$(jq -r --arg id "$pto" 'select(.id == $id) | .command' <<<"$rec")" = "/y/__toggles.sh __run pto-mode off" ]
  [ "$(jq -r --arg id "$drop" 'select(.id == $id) | .status' <<<"$rec")" = deleted ]
  [ "$(jq -r 'select(.label == "Dentist") | .when' <<<"$rec")" = "2026-10-01T10:00:00$(date -d 2026-10-01 +%:z)" ]
  [ "$(jq -r 'select(.label == "Dentist") | .action' <<<"$rec")" = show ]
  [ "$(jq -r 'select(.label == "Read the newsletter") | .repeat' <<<"$rec")" = "every 7d" ]
  [ "$(jq -r 'select(.label == "Read the newsletter") | .action' <<<"$rec")" = open ]
  [ "$(jq -r 'select(.label == "Read the newsletter") | .subject' <<<"$rec")" = "url:https://example.com/news" ]
  [ "$(jq -r 'select(.label == "Read the newsletter") | .origin' <<<"$rec")" = agenda ]
  grep -q -- '-q r -t 202609272130' "$TEST_AT_LOG"
}

@test "agenda apply refuses a line it cannot read before writing anything" {
  "$REMINDER" add "Keep" '2026-09-27 22:00' >/dev/null
  id="$(only_id)"
  before="$(wc -l <"$REMINDER_STORE")"
  agenda="${BATS_TEST_TMPDIR}/agenda.org"
  printf '** <2026-09-27 Sun 23:00> Keep\n   :id: %s\nthis is not a reminder line\n' "$id" >"$agenda"

  run "$REMINDER" agenda apply "$agenda"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Line 3: cannot read it"* ]]
  [ "$(wc -l <"$REMINDER_STORE")" -eq "$before" ]
}

@test "bare remind is the agenda: renders to the state file, runs the editor, and applies" {
  "$REMINDER" add "Move me" '2026-09-27 22:00' >/dev/null
  id="$(only_id)"
  printf '#!/usr/bin/env bash\nsed -i "s/22:00/20:00/" "$1"\n' >"$BIN/agenda-editor"
  chmod +x "$BIN/agenda-editor"

  run env REMINDER_EDITOR="$BIN/agenda-editor" "$REMINDER"

  [ "$status" -eq 0 ]
  [ -f "$REMINDER_STATE_DIR/agenda.org" ]
  grep -q "^\*\* <2026-09-27 Sun 20:00> Move me" "$REMINDER_STATE_DIR/agenda.org"
  grep -q "^   :id: $id" "$REMINDER_STATE_DIR/agenda.org"
  [ "$(last_record | jq -r '.when')" = "2026-09-27T20:00:00$(date -d 2026-09-27 +%:z)" ]
}

@test "the empty Argos applet stays available for adding a reminder" {
  cat >"$BIN/reminder-helper" <<'STUB'
#!/usr/bin/env bash
[ "$1" = list ] && printf '[]\n'
STUB
  chmod +x "$BIN/reminder-helper"

  run env REMINDER_HELPER="$BIN/reminder-helper" "$ARGOS"

  [ "$status" -eq 0 ]
  [[ "$output" == *"color='#666666'>0</span>"* ]]
  [[ "$output" != *"overdue"* ]]
  [[ "$output" == *"Open agenda"* ]]
  [[ "$output" == *"add-dialog"* ]]
}
