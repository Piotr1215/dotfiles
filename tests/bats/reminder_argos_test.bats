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
  export REMINDER_CRON_RUN="/opt/cron/__cron_run.sh"
  export REMINDER_CRON_EVERY="/opt/cron/__cron_every.sh"
  export TEST_ATQ="${BATS_TEST_TMPDIR}/atq"
  export TEST_AT_BODIES="${BATS_TEST_TMPDIR}/at-bodies"
  export TEST_AT_LOG="${BATS_TEST_TMPDIR}/at.log"
  export TEST_ATRM="${BATS_TEST_TMPDIR}/atrm.log"
  export TEST_NEXT_JOB="${BATS_TEST_TMPDIR}/next-job"
  export TEST_CRONTAB="${BATS_TEST_TMPDIR}/crontab"
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
  "$REMINDER" add "Old label" '2026-09-10 09:30' --subject 'link: https://vodafone.de/kontakt' >/dev/null
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

@test "the Argos applet renders from list --json with safe labels and id-only actions" {
  cat >"$BIN/reminder-helper" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = list ]; then
  cat <<'JSON'
[
 {"id":"0a1b2c3d","label":"Plan | <review>","when":"2026-09-10T09:30:00+02:00","action":"show","status":"active","title":"Plan | <review>","url":"https://vodafone.de/kontakt","subject":"text:link: https://vodafone.de/kontakt","overdue":false},
 {"id":"deadbeef","label":"Weekly","repeat":"0 9 * * 1","action":"show","status":"active","title":"Weekly","url":"","overdue":false},
 {"id":"0badf00d","label":"Briefing","when":"2026-09-11T09:00:00+02:00","action":"show","status":"active","title":"Briefing","url":"","subject":"text:first line of context\nsecond line\nthird line","overdue":false}
]
JSON
fi
STUB
  chmod +x "$BIN/reminder-helper"

  run env REMINDER_HELPER="$BIN/reminder-helper" "$ARGOS"

  [ "$status" -eq 0 ]
  [[ "$output" == *">3</span>"* ]]
  [[ "$output" == *"Plan ¦ &lt;review&gt;"* ]]
  [[ "$output" == *"--first line of context |"* ]]
  [[ "$output" != *"second line"* ]]
  [[ "$output" == *"--Thu 10 Sep 09:30 |"* ]]
  [[ "$output" == *"open 0a1b2c3d"* ]]
  [[ "$output" == *"edit-dialog 0a1b2c3d"* ]]
  [[ "$output" == *"done 0a1b2c3d"* ]]
  [[ "$output" == *"delete-dialog 0a1b2c3d"* ]]
  [[ "$output" == *"--repeats 0 9 * * 1 |"* ]]
  [[ "$output" != *"open deadbeef"* ]]
  ! grep "bash=" <<<"$output" | grep -q "vodafone.de"
}

@test "the empty Argos applet stays available for adding a reminder" {
  cat >"$BIN/reminder-helper" <<'STUB'
#!/usr/bin/env bash
[ "$1" = list ] && printf '[]\n'
STUB
  chmod +x "$BIN/reminder-helper"

  run env REMINDER_HELPER="$BIN/reminder-helper" "$ARGOS"

  [ "$status" -eq 0 ]
  [[ "$output" == *">0</span>"* ]]
  [[ "$output" == *"No active reminders"* ]]
  [[ "$output" == *"add-dialog"* ]]
}
