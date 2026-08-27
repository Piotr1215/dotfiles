#!/usr/bin/env bats

setup() {
  REMINDER="${BATS_TEST_DIRNAME}/../../scripts/__reminder.sh"
  GTK_GUI="${BATS_TEST_DIRNAME}/../../scripts/__reminder_gui.py"
  ARGOS="${BATS_TEST_DIRNAME}/../../.config/argos/reminders.30s.sh"
  BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$BIN"

  export REMINDER_STATE_FILE="${BATS_TEST_TMPDIR}/reminders.tsv"
  export TEST_ATQ="${BATS_TEST_TMPDIR}/atq"
  export TEST_AT_STDIN="${BATS_TEST_TMPDIR}/at.stdin"
  export TEST_AT_ARGS="${BATS_TEST_TMPDIR}/at.args"
  export TEST_ATRM="${BATS_TEST_TMPDIR}/atrm.log"
  export TEST_NEXT_JOB="${BATS_TEST_TMPDIR}/next-job"
  export TEST_OPENER_LOG="${BATS_TEST_TMPDIR}/opener.log"
  export TEST_ALERT_REQUEST="${BATS_TEST_TMPDIR}/alert.json"
  export REMINDER_GUI="$BIN/reminder-gui"
  export REMINDER_URL_OPENER="$BIN/url-opener"
  export PATH="$BIN:$PATH"

  : >"$TEST_ATQ"
  printf '42\n' >"$TEST_NEXT_JOB"

  cat >"$BIN/at" <<'EOF'
#!/usr/bin/env bash
cat >"$TEST_AT_STDIN"
printf '%s\n' "$*" >"$TEST_AT_ARGS"
job_id="$(<"$TEST_NEXT_JOB")"
printf 'warning: commands will be executed using /bin/sh\n' >&2
printf 'job %s at Sun Aug 16 14:40:00 2026\n' "$job_id" >&2
EOF

  cat >"$BIN/atq" <<'EOF'
#!/usr/bin/env bash
cat "$TEST_ATQ"
EOF

  cat >"$BIN/atrm" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_ATRM"
EOF

  cat >"$BIN/url-opener" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_OPENER_LOG"
EOF

  chmod +x "$BIN/at" "$BIN/atq" "$BIN/atrm" "$BIN/url-opener"
}

encode() {
  printf '%s' "$1" | base64 -w0
}

# A state row is "job_id \t base64(text) \t base64(notes)". Empty notes encode
# to an empty string, so a reminder without notes still writes three fields.
row() {
  printf '%s\t%s\t%s' "$1" "$(encode "$2")" "$(encode "${3:-}")"
}

@test "scheduling records the at job without putting raw text in the job" {
  run "$REMINDER" "Don't blink" 10m

  [ "$status" -eq 0 ]
  encoded="$(encode "Don't blink")"
  [ "$(<"$REMINDER_STATE_FILE")" = "$(row 42 "Don't blink")" ]
  [ "$(<"$TEST_AT_ARGS")" = "now + 10 minutes" ]
  [[ "$(<"$TEST_AT_STDIN")" == *"--notify $encoded"* ]]
  [[ "$(<"$TEST_AT_STDIN")" != *"Don't blink"* ]]
}

@test "scheduling carries the graphical display into the at job" {
  run env DISPLAY=:77 "$REMINDER" "Show the dialog" 10m

  [ "$status" -eq 0 ]
  [[ "$(<"$TEST_AT_STDIN")" == DISPLAY=:77\ * ]]
}

@test "records merge tracked reminders with active at jobs and prune stale state" {
  active="$(encode 'Review plan')"
  stale="$(encode 'Old reminder')"
  printf '42\t%s\n99\t%s\n' "$active" "$stale" >"$REMINDER_STATE_FILE"
  cat >"$TEST_ATQ" <<'EOF'
42 Sun Aug 16 14:40:00 2026 a decoder
7 Mon Aug 17 09:00:00 2026 a decoder
EOF

  run "$REMINDER" --records

  [ "$status" -eq 0 ]
  [[ "$output" == *$'42\tSun Aug 16 14:40:00 2026\t'"$active"* ]]
  [[ "$output" == *$'7\tMon Aug 17 09:00:00 2026\t'* ]]
  [[ "$output" != *$'99\t'* ]]
  [ "$(<"$REMINDER_STATE_FILE")" = "$(row 42 'Review plan')" ]
}

@test "editing schedules the replacement before removing the old job" {
  original="$(encode 'Original reminder')"
  edited="$(encode 'Edited reminder')"
  printf '42\t%s\n' "$original" >"$REMINDER_STATE_FILE"
  printf '42 Sun Aug 16 14:40:00 2026 a decoder\n' >"$TEST_ATQ"
  printf '43\n' >"$TEST_NEXT_JOB"

  cat >"$REMINDER_GUI" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf '{"message":"Edited reminder","when":"20m"}\n'
EOF
  chmod +x "$REMINDER_GUI"

  run "$REMINDER" --edit-dialog 42

  [ "$status" -eq 0 ]
  [ "$(<"$TEST_ATRM")" = "42" ]
  [ "$(<"$REMINDER_STATE_FILE")" = "$(row 43 'Edited reminder')" ]
}

@test "editing only the text keeps the existing reminder time" {
  original="$(encode 'Original reminder')"
  edited="$(encode 'New description')"
  printf '42\t%s\n' "$original" >"$REMINDER_STATE_FILE"
  printf '42 Sun Aug 16 14:40:00 2026 a decoder\n' >"$TEST_ATQ"
  printf '43\n' >"$TEST_NEXT_JOB"

  cat >"$REMINDER_GUI" <<'EOF'
#!/usr/bin/env bash
request="$(cat)"
jq -nc --arg when "$(jq -r '.when // ""' <<<"$request")" \
  '{message:"New description", when:$when}'
EOF
  chmod +x "$REMINDER_GUI"

  run "$REMINDER" --edit-dialog 42

  [ "$status" -eq 0 ]
  [ "$(<"$TEST_AT_ARGS")" = "-t 202608161440" ]
  [ "$(<"$TEST_ATRM")" = "42" ]
  [ "$(<"$REMINDER_STATE_FILE")" = "$(row 43 'New description')" ]
}

@test "an untracked at job can be named without reading its job body" {
  named="$(encode 'Run eval with Codex')"
  printf '7 Mon Aug 17 09:00:00 2026 a decoder\n' >"$TEST_ATQ"
  cat >"$REMINDER_GUI" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf '{"message":"Run eval with Codex"}\n'
EOF
  chmod +x "$REMINDER_GUI"

  run "$REMINDER" --adopt-dialog 7

  [ "$status" -eq 0 ]
  [ "$(<"$REMINDER_STATE_FILE")" = "$(row 7 'Run eval with Codex')" ]
}

@test "the GTK add form returns reminder text and schedule together" {
  cat >"$REMINDER_GUI" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf '{"message":"Stand up","when":"15m"}\n'
EOF
  chmod +x "$REMINDER_GUI"

  run "$REMINDER" --add-dialog

  [ "$status" -eq 0 ]
  [ "$(<"$REMINDER_STATE_FILE")" = "$(row 42 'Stand up')" ]
  [ "$(<"$TEST_AT_ARGS")" = "now + 15 minutes" ]
}

@test "the GTK reminder UI passes its dependency check" {
  run "$GTK_GUI" --check

  [ "$status" -eq 0 ]
  [ "$output" = "GTK 3 ready; position=center-always" ]
}

@test "the Argos applet renders a safe count and ID-only actions" {
  tracked="$(encode 'Plan | <review>')"
  cat >"$BIN/reminder-helper" <<EOF
#!/usr/bin/env bash
if [ "\$1" = --records ]; then
  printf '42\\tSun Aug 16 14:40:00 2026\\t%s\\n' '$tracked'
  printf '7\\tMon Aug 17 09:00:00 2026\\t\\n'
fi
EOF
  chmod +x "$BIN/reminder-helper"

  run env REMINDER_HELPER="$BIN/reminder-helper" "$ARGOS"

  [ "$status" -eq 0 ]
  [[ "$output" == *">2</span>"* ]]
  [[ "$output" == *"Add reminder"* ]]
  [[ "$output" == *"Plan ¦ &lt;review&gt;"* ]]
  [[ "$output" == *"--edit-dialog 42"* ]]
  [[ "$output" == *"--cancel-dialog 42"* ]]
  [[ "$output" == *"Untracked at job 7"* ]]
  [[ "$output" == *"--adopt-dialog 7"* ]]
  [[ "$output" != *"--edit-dialog 7"* ]]
}

@test "the empty Argos applet stays available for adding a reminder" {
  cat >"$BIN/reminder-helper" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$BIN/reminder-helper"

  run env REMINDER_HELPER="$BIN/reminder-helper" "$ARGOS"

  [ "$status" -eq 0 ]
  [[ "$output" == *">0</span>"* ]]
  [[ "$output" == *"No active reminders"* ]]
  [[ "$output" == *"Add reminder"* ]]
}

@test "notes travel base64 into the job body and the state row" {
  run "$REMINDER" 'Call vodafone' 2h --note 'link: https://vodafone.de/kontakt'

  [ "$status" -eq 0 ]
  [ "$(<"$REMINDER_STATE_FILE")" = "$(row 42 'Call vodafone' 'link: https://vodafone.de/kontakt')" ]
  [ "$(<"$TEST_AT_ARGS")" = "now + 2 hours" ]
  [[ "$(<"$TEST_AT_STDIN")" == *"$(encode 'link: https://vodafone.de/kontakt')"* ]]
  [[ "$(<"$TEST_AT_STDIN")" != *"vodafone.de"* ]]
}

@test "open-link prefers a labelled link over a bare url" {
  row 42 'Call vodafone' 'context https://example.com/other
link: https://vodafone.de/kontakt' >"$REMINDER_STATE_FILE"

  run "$REMINDER" --open-link 42

  [ "$status" -eq 0 ]
  [ "$(<"$TEST_OPENER_LOG")" = "https://vodafone.de/kontakt" ]
}

@test "open-link falls back to the first bare url in the notes" {
  row 42 'Read this' 'see https://example.com/a then https://example.com/b' >"$REMINDER_STATE_FILE"

  run "$REMINDER" --open-link 42

  [ "$status" -eq 0 ]
  [ "$(<"$TEST_OPENER_LOG")" = "https://example.com/a" ]
}

@test "open-link on a reminder with no url reports instead of opening" {
  row 42 'Plain reminder' 'just some context, no link at all' >"$REMINDER_STATE_FILE"
  cat >"$REMINDER_GUI" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf '{"closed":true}\n'
EOF
  chmod +x "$REMINDER_GUI"

  run "$REMINDER" --open-link 42

  [ "$status" -ne 0 ]
  [ ! -s "$TEST_OPENER_LOG" ]
}

@test "a state row written before notes existed still edits and gains notes" {
  printf '42\t%s\n' "$(encode 'Legacy reminder')" >"$REMINDER_STATE_FILE"
  printf '42 Sun Aug 16 14:40:00 2026 a decoder\n' >"$TEST_ATQ"
  printf '43\n' >"$TEST_NEXT_JOB"
  cat >"$REMINDER_GUI" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf '{"message":"Legacy reminder","when":"20m","notes":"link: https://example.com/x"}\n'
EOF
  chmod +x "$REMINDER_GUI"

  run "$REMINDER" --edit-dialog 42

  [ "$status" -eq 0 ]
  [ "$(<"$TEST_ATRM")" = "42" ]
  [ "$(<"$REMINDER_STATE_FILE")" = "$(row 43 'Legacy reminder' 'link: https://example.com/x')" ]
}

@test "a fired reminder hands its notes and resolved url to the alert" {
  cat >"$REMINDER_GUI" <<'EOF'
#!/usr/bin/env bash
cat >"$TEST_ALERT_REQUEST"
printf '{"action":""}\n'
EOF
  chmod +x "$REMINDER_GUI"

  run "$REMINDER" --notify "$(encode 'Call vodafone')" "$(encode 'link: https://vodafone.de/kontakt')"

  [ "$status" -eq 0 ]
  [ "$(jq -r '.message' <"$TEST_ALERT_REQUEST")" = "Call vodafone" ]
  [ "$(jq -r '.notes' <"$TEST_ALERT_REQUEST")" = "link: https://vodafone.de/kontakt" ]
  [ "$(jq -r '.url' <"$TEST_ALERT_REQUEST")" = "https://vodafone.de/kontakt" ]
}

@test "a reminder queued before notes existed still fires" {
  cat >"$REMINDER_GUI" <<'EOF'
#!/usr/bin/env bash
cat >"$TEST_ALERT_REQUEST"
printf '{"action":""}\n'
EOF
  chmod +x "$REMINDER_GUI"

  run "$REMINDER" --notify "$(encode 'Old style reminder')"

  [ "$status" -eq 0 ]
  [ "$(jq -r '.message' <"$TEST_ALERT_REQUEST")" = "Old style reminder" ]
  [ "$(jq -r '.url' <"$TEST_ALERT_REQUEST")" = "" ]
}

@test "the Argos applet offers Open link and passes the job id, never the url" {
  tracked="$(encode 'Call vodafone')"
  noted="$(encode 'link: https://vodafone.de/kontakt')"
  cat >"$BIN/reminder-helper" <<EOF
#!/usr/bin/env bash
if [ "\$1" = --records ]; then
  printf '42\\tSun Aug 16 14:40:00 2026\\t%s\\t%s\\n' '$tracked' '$noted'
fi
EOF
  chmod +x "$BIN/reminder-helper"

  run env REMINDER_HELPER="$BIN/reminder-helper" "$ARGOS"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Open link"* ]]
  [[ "$output" == *"--open-link 42"* ]]
  [[ "$output" == *"link: https://vodafone.de/kontakt"* ]]
  ! grep -q "bash=.*vodafone\.de" <<<"$output"
}

@test "the Argos applet omits Open link when the notes carry no url" {
  tracked="$(encode 'Call vodafone')"
  noted="$(encode 'ask about the router swap')"
  cat >"$BIN/reminder-helper" <<EOF
#!/usr/bin/env bash
if [ "\$1" = --records ]; then
  printf '42\\tSun Aug 16 14:40:00 2026\\t%s\\t%s\\n' '$tracked' '$noted'
fi
EOF
  chmod +x "$BIN/reminder-helper"

  run env REMINDER_HELPER="$BIN/reminder-helper" "$ARGOS"

  [ "$status" -eq 0 ]
  [[ "$output" == *"ask about the router swap"* ]]
  [[ "$output" != *"Open link"* ]]
  [[ "$output" != *"--open-link"* ]]
}
