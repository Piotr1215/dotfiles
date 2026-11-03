#!/usr/bin/env bats

setup() {
  REMINDER="$BATS_TEST_DIRNAME/../../scripts/__reminder.sh"
  export REMINDER_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export REMINDER_STORE="$REMINDER_STATE_DIR/reminders.jsonl"
  export REMINDER_OWN_CLOCKS=1
  export CLOCK_LOG="$BATS_TEST_TMPDIR/clocks.log"
  export TEST_CRONTAB="$BATS_TEST_TMPDIR/crontab"
  export CRON_EVERY_STAMP_DIR="$BATS_TEST_TMPDIR/stamps"
  mkdir -p "$REMINDER_STATE_DIR" "$BATS_TEST_TMPDIR/bin"
  : >"$CLOCK_LOG"
  for cmd in atq at atrm crontab; do
    cat >"$BATS_TEST_TMPDIR/bin/$cmd" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "${0##*/}" >>"$CLOCK_LOG"
exit 0
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/$cmd"
  done
  cat >"$BATS_TEST_TMPDIR/bin/crontab" <<'STUB'
#!/usr/bin/env bash
printf 'crontab\n' >>"$CLOCK_LOG"
case "$1" in -l) [ ! -f "$TEST_CRONTAB" ] || cat "$TEST_CRONTAB" ;; -) cat >"$TEST_CRONTAB" ;; esac
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/crontab"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "sync puts frequent exec checks behind one five minute dispatcher" {
  for i in {1..8}; do
    printf '{"id":"%08x","status":"active","action":"exec","command":"true","repeat":"* * * * *"}\n' "$i"
  done >"$REMINDER_STORE"
  printf '%s\n' '{"id":"eeeeeeee","status":"active","action":"exec","command":"true","repeat":"every 3m","deadline":"2030-01-01T09:00:00+00:00"}' >>"$REMINDER_STORE"
  printf '%s\n' '{"id":"aaaaaaaa","status":"active","action":"show","repeat":"0 9 * * *"}' >>"$REMINDER_STORE"
  printf '%s\n' '{"id":"bbbbbbbb","status":"active","action":"exec","command":"true","when":"2030-01-01T10:00:00+00:00"}' >>"$REMINDER_STORE"
  run "$REMINDER" sync
  [ "$status" -eq 0 ]
  [ "$(grep -c '^\*/5 \* \* \* \* .*__reminder_dispatch.py' "$TEST_CRONTAB")" -eq 1 ]
  ! grep -q '^\* \* \* \* \* ' "$TEST_CRONTAB"
  ! grep -q 'remind-eeeeeeee' "$TEST_CRONTAB"
  grep -q '^0 9 \* \* \* .*remind-aaaaaaaa' "$TEST_CRONTAB"
  [ "$(grep -c '^at$' "$CLOCK_LOG")" -eq 2 ]
}

@test "unresolved recurring exec leaves the clocks alone" {
  printf '%s\n' '{"id":"deadbeef","status":"active","action":"exec","command":"true","repeat":"* * * * *"}' >"$REMINDER_STORE"
  run "$REMINDER" fire deadbeef
  [ "$status" -eq 0 ]
  [ ! -s "$CLOCK_LOG" ]
  jq -se 'last | .status == "active" and .repeat == "* * * * *" and .when == null' "$REMINDER_STORE"
}

@test "sync rejects an every-minute poll before changing the crontab" {
  : >"$REMINDER_STORE"
  printf '* * * * * /bin/true\n' >"$TEST_CRONTAB"
  run "$REMINDER" sync
  [ "$status" -ne 0 ]
  [ "$(cat "$TEST_CRONTAB")" = '* * * * * /bin/true' ]
}

@test "unresolved recurring exec removes a pending one-shot and syncs" {
  printf '%s\n' '{"id":"deadbeef","status":"active","action":"exec","command":"true","repeat":"* * * * *","when":"2030-01-01T09:00:00+00:00"}' >"$REMINDER_STORE"
  run "$REMINDER" fire deadbeef
  [ "$status" -eq 0 ]
  grep -qx atq "$CLOCK_LOG"
  jq -se 'last | .status == "active" and .repeat == "* * * * *" and .when == null' "$REMINDER_STORE"
}

@test "a pending one-shot added during the command is removed and synced" {
  cat >"$BATS_TEST_TMPDIR/edit-record" <<'STUB'
#!/usr/bin/env bash
record=$(tail -n1 "$REMINDER_STORE")
jq -c '.when = "2030-01-01T09:00:00+00:00"' <<<"$record" >>"$REMINDER_STORE"
STUB
  chmod +x "$BATS_TEST_TMPDIR/edit-record"
  jq -nc --arg command "$BATS_TEST_TMPDIR/edit-record" '{id:"deadbeef",status:"active",action:"exec",command:$command,repeat:"* * * * *"}' >"$REMINDER_STORE"
  run "$REMINDER" fire deadbeef
  [ "$status" -eq 0 ]
  grep -qx atq "$CLOCK_LOG"
  jq -se 'last | .status == "active" and .when == null' "$REMINDER_STORE"
}

@test "unresolved one-shot exec completes and syncs" {
  printf '%s\n' '{"id":"deadbeef","status":"active","action":"exec","command":"true","when":"2030-01-01T09:00:00+00:00"}' >"$REMINDER_STORE"
  run "$REMINDER" fire deadbeef
  [ "$status" -eq 0 ]
  grep -qx atq "$CLOCK_LOG"
  jq -se 'last | .status == "done" and .when == null' "$REMINDER_STORE"
}
