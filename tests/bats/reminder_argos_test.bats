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
  export REMINDER_GUI="$BIN/reminder-gui"
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

  chmod +x "$BIN/at" "$BIN/atq" "$BIN/atrm"
}

encode() {
  printf '%s' "$1" | base64 -w0
}

@test "scheduling records the at job without putting raw text in the job" {
  run "$REMINDER" "Don't blink" 10m

  [ "$status" -eq 0 ]
  encoded="$(encode "Don't blink")"
  [ "$(<"$REMINDER_STATE_FILE")" = $'42\t'"$encoded" ]
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
  [[ "$(<"$REMINDER_STATE_FILE")" == $'42\t'"$active" ]]
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
  [[ "$(<"$REMINDER_STATE_FILE")" == $'43\t'"$edited" ]]
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
  [[ "$(<"$REMINDER_STATE_FILE")" == $'43\t'"$edited" ]]
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
  [[ "$(<"$REMINDER_STATE_FILE")" == $'7\t'"$named" ]]
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
  encoded="$(encode 'Stand up')"
  [[ "$(<"$REMINDER_STATE_FILE")" == $'42\t'"$encoded" ]]
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
