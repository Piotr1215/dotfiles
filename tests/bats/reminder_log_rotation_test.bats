#!/usr/bin/env bats

setup() {
  REMINDER="$BATS_TEST_DIRNAME/../../scripts/__reminder.sh"
  export REMINDER_STATE_DIR="$BATS_TEST_TMPDIR/state with spaces"
  export REMINDER_LOG="$REMINDER_STATE_DIR/fire.log"
  export REMINDER_STORE="$REMINDER_STATE_DIR/reminders.jsonl"
  mkdir -p "$REMINDER_STATE_DIR"
}

# A complete record that reaches the production threshold without real fires.
large_log() {
  printf '2026-11-03T10:00:00+01:00\tcafef00d\texec\trc=1\t%1048576s\n' "$1" >"$REMINDER_LOG"
}

@test "rotation leaves missing and small logs alone" {
  run "$REMINDER" rotate-log
  [ "$status" -eq 0 ]
  [ ! -e "$REMINDER_LOG" ]
  printf 'small log\n' >"$REMINDER_LOG"
  run "$REMINDER" rotate-log
  [ "$status" -eq 0 ]
  [ "$(cat "$REMINDER_LOG")" = 'small log' ]
  [ ! -e "$REMINDER_LOG.1" ]
  [ ! -e "$REMINDER_STORE" ]
}

@test "rotation preserves every byte and the log mode without changing the store" {
  large_log original
  chmod 640 "$REMINDER_LOG"
  cp "$REMINDER_LOG" "$BATS_TEST_TMPDIR/expected"
  printf '{"id":"deadbeef","status":"active"}\n' >"$REMINDER_STORE"
  cp "$REMINDER_STORE" "$BATS_TEST_TMPDIR/store"
  run "$REMINDER" rotate-log
  [ "$status" -eq 0 ]
  [ ! -s "$REMINDER_LOG" ]
  [ "$(stat -c %a "$REMINDER_LOG")" = 640 ]
  cmp "$BATS_TEST_TMPDIR/expected" "$REMINDER_LOG.1"
  cmp "$BATS_TEST_TMPDIR/store" "$REMINDER_STORE"
}

@test "three prior generations are retained and older ones are compressed" {
  for generation in 1 2 3 4; do
    large_log "generation-$generation"
    "$REMINDER" rotate-log
  done
  grep -q 'generation-4$' "$REMINDER_LOG.1"
  gzip -cd "$REMINDER_LOG.2.gz" | grep -q 'generation-3$'
  gzip -cd "$REMINDER_LOG.3.gz" | grep -q 'generation-2$'
  [ ! -e "$REMINDER_LOG.4.gz" ]
  [ ! -e "$REMINDER_LOG.2.gz.tmp" ]
}

@test "concurrent fires rotate once and preserve all appended records" {
  large_log original
  cp "$REMINDER_LOG" "$BATS_TEST_TMPDIR/expected"
  for id in $(seq 1 16); do
    "$REMINDER" fire "$(printf '%08x' "$id")" &
  done
  wait
  cmp "$BATS_TEST_TMPDIR/expected" "$REMINDER_LOG.1"
  [ "$(wc -l <"$REMINDER_LOG")" -eq 16 ]
  [ "$(cut -f 2 "$REMINDER_LOG" | sort -u | wc -l)" -eq 16 ]
  [ "$(awk -F '\t' '$3 == "missing" { n++ } END { print n }' "$REMINDER_LOG")" -eq 16 ]
  [ ! -e "$REMINDER_LOG.2.gz" ]
}

@test "a compression failure preserves the active log and previous archive" {
  large_log previous
  "$REMINDER" rotate-log
  cp "$REMINDER_LOG.1" "$BATS_TEST_TMPDIR/previous"
  large_log current
  cp "$REMINDER_LOG" "$BATS_TEST_TMPDIR/current"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/usr/bin/env bash\nexit 42\n' >"$BATS_TEST_TMPDIR/bin/gzip"
  chmod +x "$BATS_TEST_TMPDIR/bin/gzip"
  run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" "$REMINDER" rotate-log
  [ "$status" -eq 42 ]
  cmp "$BATS_TEST_TMPDIR/current" "$REMINDER_LOG"
  cmp "$BATS_TEST_TMPDIR/previous" "$REMINDER_LOG.1"
  [ ! -e "$REMINDER_LOG.2.gz" ]
}

@test "the agenda reads the latest retained firing after rotation" {
  printf '{"id":"deadbeef","status":"active","label":"history test","action":"show"}\n' >"$REMINDER_STORE"
  large_log padding
  printf '2026-11-03T11:00:00+01:00\tdeadbeef\tfired\tshow\thistory test\n' >>"$REMINDER_LOG"
  printf '2026-11-03T11:00:01+01:00\tdeadbeef\tdone\tshow\thistory test\n' >>"$REMINDER_LOG"
  "$REMINDER" rotate-log
  large_log unrelated
  "$REMINDER" rotate-log
  run "$REMINDER" agenda render
  [ "$status" -eq 0 ]
  [[ "$output" == *':last: [2026-11-03 Tue 11:00] done'* ]]
}
