#!/usr/bin/env bats

# Notification triggers (docs/notify-triggers.md): a popup line in a scratch
# notification log drives `remind match`; at, atq, atrm, crontab and tmuxinator
# are stubs that record what they were asked. Nothing here touches the real
# store, at queue or crontab (REMINDER_OWN_CLOCKS marks the stubs as this
# store's own clocks).

setup() {
  REMINDER="${BATS_TEST_DIRNAME}/../../scripts/__reminder.sh"
  BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "$BIN"

  export REMINDER_STATE_DIR="${BATS_TEST_TMPDIR}/state"
  export REMINDER_STORE="${REMINDER_STATE_DIR}/reminders.jsonl"
  export REMINDER_LOG="${REMINDER_STATE_DIR}/fire.log"
  export REMINDER_GUI="$BIN/reminder-gui"
  export REMINDER_MAILER="$BIN/mailer"
  export REMINDER_CRON_RUN="/opt/cron/__cron_run.sh"
  export REMINDER_CRON_EVERY="/opt/cron/__cron_every.sh"
  export CRON_EVERY_STAMP_DIR="${BATS_TEST_TMPDIR}/cron-every"
  export NOTIFY_LOG="${BATS_TEST_TMPDIR}/notifications.log"
  export REMINDER_OWN_CLOCKS=1
  export REMINDER_NOTIFY_POLL=1
  export TEST_AT_LOG="${BATS_TEST_TMPDIR}/at.log"
  export TEST_AT_BODIES="${BATS_TEST_TMPDIR}/at-bodies"
  export TEST_CRONTAB="${BATS_TEST_TMPDIR}/crontab"
  export TEST_MAIL_LOG="${BATS_TEST_TMPDIR}/mail.log"
  export TEST_TMUXINATOR_LOG="${BATS_TEST_TMPDIR}/tmuxinator.log"
  export PATH="$BIN:$PATH"
  mkdir -p "$REMINDER_STATE_DIR" "$TEST_AT_BODIES"
  : >"$NOTIFY_LOG"
  : >"$TEST_CRONTAB"
  # A first pass with no cursor starts at the end of the log; these tests
  # write popups before their first pass, so the cursor starts at 0.
  printf '0' >"$REMINDER_STATE_DIR/notify.cursor"

  cat >"$BIN/at" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_AT_LOG"
cat >"$TEST_AT_BODIES/$(date +%s%N)"
printf 'job 7 at %s\n' "$(date)" >&2
STUB
  printf '#!/usr/bin/env bash\n' >"$BIN/atq"
  printf '#!/usr/bin/env bash\n' >"$BIN/atrm"
  printf '#!/usr/bin/env bash\n' >"$BIN/reminder-gui"
  cat >"$BIN/crontab" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = -l ]; then cat "$TEST_CRONTAB"; else cat >"$TEST_CRONTAB"; fi
STUB
  printf '#!/usr/bin/env bash\n{ printf "subject: %%s\\n" "$1"; cat; } >>"$TEST_MAIL_LOG"\n' >"$BIN/mailer"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"$TEST_TMUXINATOR_LOG"\n' >"$BIN/tmuxinator"
  printf '#!/usr/bin/env bash\nexit 1\n' >"$BIN/tmux"
  chmod +x "$BIN"/*
}

# A notification log record: now (or an offset date -d accepts), app, summary, body.
popup() {
  printf '%s\t%s\t%s\t%s\n' "$(date -d "${1:-now}" '+%F %T')" "$2" "$3" "$4" >>"$NOTIFY_LOG"
}

standup_rule() {
  "$REMINDER" add "start standup session" --on-notify '\t\[vcluster-internal\] from Standup and Prosper\tHeads up! Your standup' \
    --action exec --command 'tmux has-session -t standup || tmuxinator start standup --no-attach' \
    --origin claude --to gordon "$@" | sed -n 's/^Added \([0-9a-f]*\):.*/\1/p'
}

standup_popup() {
  popup "${1:-now}" "" "[vcluster-internal] from Standup and Prosper" "Heads up! Your standup in *<#C08QS1CLT9A>* will be reported in 15 minutes."
}

@test "add --on-notify stores the pattern, lists it as on popup, and sync derives the pattern file" {
  id="$(standup_rule)"
  [ -n "$id" ]
  run jq -r '[.delay // "none", .when // "none", .repeat // "none", .action, .to, .origin, .status] | join(" ")' "$REMINDER_STORE"
  [ "$output" = "none none none exec gordon claude active" ]
  [ "$(jq -r '.on_notify' "$REMINDER_STORE")" = '\t\[vcluster-internal\] from Standup and Prosper\tHeads up! Your standup' ]
  run "$REMINDER" list
  [[ "$output" == "$id  on popup"* ]]
  [[ "$output" == *"exec   start standup session" ]]
  run "$REMINDER" list --json
  [ "$(jq -r '.[0].on_notify' <<<"$output")" = '\t\[vcluster-internal\] from Standup and Prosper\tHeads up! Your standup' ]
  [ "$(cat "$REMINDER_STATE_DIR/notify-patterns.txt")" = '\t\[vcluster-internal\] from Standup and Prosper\tHeads up! Your standup' ]
  [ ! -s "$TEST_AT_LOG" ]
  ! grep -q "fire $id" "$TEST_CRONTAB"
}

@test "add refuses a pattern with a clock, a non-exec action, a bad regex, and a lone delay" {
  run "$REMINDER" add "x" 10m --on-notify 'a' --action exec --command true
  [ "$status" -ne 0 ] && [[ "$output" == *"takes no time or repeat"* ]]
  run "$REMINDER" add "x" --on-notify 'a' --repeat 'every 1h' --action exec --command true
  [ "$status" -ne 0 ] && [[ "$output" == *"takes no time or repeat"* ]]
  run "$REMINDER" add "x" --on-notify 'a'
  [ "$status" -ne 0 ] && [[ "$output" == *"needs --action exec"* ]]
  run "$REMINDER" add "x" --on-notify 'a(' --action exec --command true
  [ "$status" -ne 0 ] && [[ "$output" == *"Cannot compile pattern"* ]]
  run "$REMINDER" add "x" 10m --delay 5m
  [ "$status" -ne 0 ] && [[ "$output" == *"--delay needs --on-notify"* ]]
  run "$REMINDER" add "x" --on-notify 'a' --delay 5 --action exec --command true
  [ "$status" -ne 0 ] && [[ "$output" == *"Cannot parse delay"* ]]
  [ ! -s "$REMINDER_STORE" ]
}

@test "a fresh matching popup fires the command with the record on stdin and in REMINDER_MATCH, and the reminder stays active" {
  id="$(standup_rule)"
  standup_popup
  run "$REMINDER" match
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMUXINATOR_LOG")" = "start standup --no-attach" ]
  run jq -r '.status' "$REMINDER_STORE"
  [ "${lines[-1]}" = active ]
  grep -q $'\t'"$id"$'\tfired\texec on popup' "$REMINDER_LOG"
  grep -q $'\t'"$id"$'\texec\trc=0' "$REMINDER_LOG"
  [ -f "$REMINDER_STATE_DIR/notify.alive" ]
  [ "$(cat "$REMINDER_STATE_DIR/notify.cursor")" = "$(stat -c %s "$NOTIFY_LOG")" ]
  # The popup itself reaches the command, not the shell.
  "$REMINDER" add "capture" --on-notify '\tnotify-send\tcapture\t' --action exec \
    --command "cat >$BATS_TEST_TMPDIR/stdin.txt; printf '%s' \"\$REMINDER_MATCH\" >$BATS_TEST_TMPDIR/env.txt" >/dev/null
  popup now notify-send capture "the body"
  "$REMINDER" match
  [[ "$(cat "$BATS_TEST_TMPDIR/stdin.txt")" == *$'\tnotify-send\tcapture\tthe body' ]]
  [ "$(cat "$BATS_TEST_TMPDIR/env.txt")" = "$(tail -n1 "$NOTIFY_LOG")" ]
}

@test "a popup older than the freshness window is skipped and logged as stale, silently" {
  id="$(standup_rule)"
  standup_popup '20 minutes ago'
  standup_popup '13 days ago'
  "$REMINDER" match
  [ ! -f "$TEST_TMUXINATOR_LOG" ]
  grep -q $'\t'"$id"$'\tstale\tpopup 20m old' "$REMINDER_LOG"
  grep -q $'\t'"$id"$'\tstale\tpopup 13d 0h old' "$REMINDER_LOG"
  ! grep -q fired "$REMINDER_LOG"
  # Nothing reaches Gordon: the mod already showed him the popup while the
  # watcher was down, so a line here would be a duplicate.
  ! grep -q $'\treminder\t' "$NOTIFY_LOG"
  [ "$(grep -c . "$NOTIFY_LOG")" -eq 2 ]
  "$REMINDER" match
  [ "$(grep -c stale "$REMINDER_LOG")" -eq 2 ]
  [ ! -f "$TEST_TMUXINATOR_LOG" ]
  # The window is a knob.
  REMINDER_NOTIFY_WINDOW=3600 standup_popup '20 minutes ago'
  REMINDER_NOTIFY_WINDOW=3600 "$REMINDER" match
  [ "$(cat "$TEST_TMUXINATOR_LOG")" = "start standup --no-attach" ]
}

@test "a delay queues an at job in queue n whose body carries only the id and a token, and the delayed fire reads the match file" {
  id="$(standup_rule --delay 10m)"
  standup_popup
  "$REMINDER" match
  [ ! -f "$TEST_TMUXINATOR_LOG" ]
  [ "$(cat "$TEST_AT_LOG")" = "-q n now + 10 minutes" ]
  body="$(cat "$TEST_AT_BODIES"/*)"
  [[ "$body" =~ __reminder\.sh\ fire\ $id\ ([0-9a-f]{16})$ ]]
  token="${BASH_REMATCH[1]}"
  [[ "$body" != *"Standup"* ]]
  [ "$(cat "$REMINDER_STATE_DIR/matches/$token")" = "$(tail -n1 "$NOTIFY_LOG")" ]
  grep -q $'\t'"$id"$'\tqueued\tfire in 10m' "$REMINDER_LOG"
  "$REMINDER" fire "$id" "$token"
  [ "$(cat "$TEST_TMUXINATOR_LOG")" = "start standup --no-attach" ]
  [ ! -e "$REMINDER_STATE_DIR/matches/$token" ]
  grep -q $'\t'"$id"$'\tfired\texec on popup (delayed)' "$REMINDER_LOG"
  # A second fire of the same token finds no match and does nothing.
  "$REMINDER" fire "$id" "$token"
  [ "$(grep -c . "$TEST_TMUXINATOR_LOG")" -eq 1 ]
  grep -q $'\t'"$id"$'\tmissing\tmatch '"$token" "$REMINDER_LOG"
}

@test "shell metacharacters in a popup stay inert" {
  "$REMINDER" add "capture" --on-notify '\tnotify-send\tevil\t' --action exec \
    --command "cat >$BATS_TEST_TMPDIR/stdin.txt" >/dev/null
  popup now notify-send evil "\$(touch $BATS_TEST_TMPDIR/pwned) \`touch $BATS_TEST_TMPDIR/pwned2\`; touch $BATS_TEST_TMPDIR/pwned3 | touch $BATS_TEST_TMPDIR/pwned4"
  "$REMINDER" match
  [ ! -e "$BATS_TEST_TMPDIR/pwned" ] && [ ! -e "$BATS_TEST_TMPDIR/pwned2" ] && [ ! -e "$BATS_TEST_TMPDIR/pwned3" ] && [ ! -e "$BATS_TEST_TMPDIR/pwned4" ]
  grep -qF '$(touch' "$BATS_TEST_TMPDIR/stdin.txt"
  # The delayed path stores the record outside the job body.
  "$REMINDER" add "capture later" --on-notify '\tnotify-send\tevil\t' --delay 1h --action exec --command true >/dev/null
  popup now notify-send evil "\$(touch $BATS_TEST_TMPDIR/pwned5)"
  "$REMINDER" match
  ! grep -qF 'touch' "$TEST_AT_BODIES"/*
  [ ! -e "$BATS_TEST_TMPDIR/pwned5" ]
}

@test "each popup fires a reminder at most once: a second pass, a cursor reset, and a crash before the fire all stay quiet" {
  id="$(standup_rule)"
  standup_popup
  "$REMINDER" match
  "$REMINDER" match
  [ "$(grep -c . "$TEST_TMUXINATOR_LOG")" -eq 1 ]
  printf '0' >"$REMINDER_STATE_DIR/notify.cursor"
  "$REMINDER" match
  [ "$(grep -c . "$TEST_TMUXINATOR_LOG")" -eq 1 ]
  grep -q $'\t'"$id"$'\tskipped\talready fired for this popup' "$REMINDER_LOG"
  # The cursor moves before the command runs, so a crash mid-fire cannot replay.
  "$REMINDER" add "crash" --on-notify '\tnotify-send\tcrash\t' --action exec --command 'kill -9 $$' >/dev/null
  popup now notify-send crash "boom"
  "$REMINDER" match || true
  [ "$(cat "$REMINDER_STATE_DIR/notify.cursor")" = "$(stat -c %s "$NOTIFY_LOG")" ]
  # Two distinct popups are two fires.
  sleep 1
  standup_popup
  "$REMINDER" match
  [ "$(grep -c . "$TEST_TMUXINATOR_LOG")" -eq 2 ]
}

@test "a failing command reports one line to Gordon, keeps the reminder active, and the error line never re-triggers" {
  id="$(standup_rule)"
  printf '#!/usr/bin/env bash\nprintf "no such project\\n"; exit 3\n' >"$BIN/tmuxinator"
  standup_popup
  "$REMINDER" match
  tail -n1 "$NOTIFY_LOG" | grep -q $'\treminder\terror: start standup session\tid:'"$id"' | exit 3 no such project'
  grep -q $'\t'"$id"$'\terror\tno such project' "$REMINDER_LOG"
  grep -q $'\t'"$id"$'\tdelivered\tgordon error' "$REMINDER_LOG"
  [ "$(jq -r '.status' "$REMINDER_STORE" | tail -n1)" = active ]
  grep -q 'exit 3' "$REMINDER_STATE_DIR/runs/$id.log"
  before="$(wc -l <"$REMINDER_LOG")"
  "$REMINDER" match
  [ "$(wc -l <"$REMINDER_LOG")" -eq "$before" ]
  # Without --to gordon the error goes to mail when asked.
  "$REMINDER" edit "$id" --to piotr --notify mail >/dev/null
  sleep 1
  standup_popup
  "$REMINDER" match
  grep -q 'subject: error: start standup session' "$TEST_MAIL_LOG"
  # A hung command ends as an error, not a stuck watcher.
  hang="$("$REMINDER" add "hang" --on-notify '\tnotify-send\thang\t' --action exec --command 'sleep 30' --to gordon | grep -oE '[0-9a-f]{8}' | head -n1)"
  popup now notify-send hang "zzz"
  REMINDER_NOTIFY_TIMEOUT=1 "$REMINDER" match
  tail -n1 "$NOTIFY_LOG" | grep -q $'\treminder\terror: hang\tid:'"$hang"' | timed out after 1s'
}

@test "edit, agenda and done treat an on-notify reminder as its own trigger kind" {
  id="$(standup_rule)"
  run "$REMINDER" edit "$id" --when 1h
  [ "$status" -ne 0 ] && [[ "$output" == *"takes no time or repeat"* ]]
  "$REMINDER" edit "$id" --delay 5m >/dev/null
  [ "$(jq -r '.delay' "$REMINDER_STORE" | tail -n1)" = 5m ]
  run "$REMINDER" list
  [[ "$output" == "$id  on popup          +5m"* ]]
  run "$REMINDER" agenda render
  [[ "$output" == *$'* On popup\n\n** start standup session\n   :on-notify: \\t\\[vcluster-internal\\] from Standup and Prosper\\tHeads up! Your standup\n   :delay: 5m\n   :action: exec\n   :runs: tmux has-session'* ]]
  "$REMINDER" agenda render >"$BATS_TEST_TMPDIR/agenda.org"
  run "$REMINDER" agenda apply "$BATS_TEST_TMPDIR/agenda.org"
  [[ "$output" == "Unchanged $id" ]]
  sed -i 's/^   :delay: 5m$/   :delay: 20m/' "$BATS_TEST_TMPDIR/agenda.org"
  "$REMINDER" agenda apply "$BATS_TEST_TMPDIR/agenda.org" >/dev/null
  [ "$(jq -r '.delay' "$REMINDER_STORE" | tail -n1)" = 20m ]
  printf '** <%s> too early\n   :on-notify: x\n   :action: exec\n   :runs: true\n' "$(date -d tomorrow '+%Y-%m-%d %a 09:00')" >>"$BATS_TEST_TMPDIR/agenda.org"
  run "$REMINDER" agenda apply "$BATS_TEST_TMPDIR/agenda.org"
  [ "$status" -ne 0 ] && [[ "$output" == *"takes no time or repeat"* ]]
  "$REMINDER" done "$id" >/dev/null
  [ "$(jq -r '.status' "$REMINDER_STORE" | tail -n1)" = done ]
  [ ! -s "$REMINDER_STATE_DIR/notify-patterns.txt" ]
  standup_popup
  "$REMINDER" match
  [ ! -f "$TEST_TMUXINATOR_LOG" ]
}

@test "a first pass with no cursor starts at the end of the log and fires nothing" {
  id="$(standup_rule)"
  rm -f "$REMINDER_STATE_DIR/notify.cursor"
  standup_popup
  "$REMINDER" match
  [ ! -f "$TEST_TMUXINATOR_LOG" ]
  [ "$(cat "$REMINDER_STATE_DIR/notify.cursor")" = "$(stat -c %s "$NOTIFY_LOG")" ]
  sleep 1
  standup_popup
  "$REMINDER" match
  [ "$(cat "$TEST_TMUXINATOR_LOG")" = "start standup --no-attach" ]
  grep -q $'\t'"$id"$'\tfired' "$REMINDER_LOG"
}

@test "watch runs match passes until stopped and touches the heartbeat" {
  standup_rule >/dev/null
  timeout 3 "$REMINDER" watch &
  watcher=$!
  sleep 1
  standup_popup
  wait "$watcher" || true
  [ "$(cat "$TEST_TMUXINATOR_LOG")" = "start standup --no-attach" ]
  [ -f "$REMINDER_STATE_DIR/notify.alive" ]
}

@test "watch with a thread url subscribes instead of running the daemon" {
  cat >"$BIN/tw" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$TEST_TW_LOG"
STUB
  chmod +x "$BIN/tw"
  export TEST_TW_LOG="${BATS_TEST_TMPDIR}/tw.log"
  THREAD_WATCH_BIN="$BIN/tw" run timeout 10 "$REMINDER" watch "https://x.slack.com/archives/C1/p1" --task abc </dev/null
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TW_LOG")" = "subscribe https://x.slack.com/archives/C1/p1 --task abc" ]
}

@test "watch with arguments fails fast when the subscriber is missing" {
  THREAD_WATCH_BIN="$BIN/missing" run timeout 10 "$REMINDER" watch "https://x/p1" </dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}
