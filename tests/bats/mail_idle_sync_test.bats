#!/usr/bin/env bats

# __mail_idle_sync.sh against a stub mbsync and a throwaway notmuch database,
# never the live one. The stub mbsync moves messages from a fake remote into
# the maildir for the boxes it is asked to sync and records every call; a
# stub post-new hook records each `notmuch new`; stub notify-send records
# popups; stub pgrep plays the display server and any foreign mbsync.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__mail_idle_sync.sh"
  WORK="$(mktemp -d)"
  MAILDIR="${WORK}/mail"
  REMOTE="${WORK}/remote"
  ACCT="piotr.zaniewski@loft.sh"
  mkdir -p "${MAILDIR}/.notmuch/hooks" "${WORK}/bin" "$REMOTE"

  export NOTMUCH_CONFIG="${WORK}/notmuch-config"
  cat >"$NOTMUCH_CONFIG" <<EOF
[database]
path=${MAILDIR}
[user]
primary_email=piotrzan@gmail.com
other_email=piotr.zaniewski@loft.sh
[new]
tags=unread;inbox;
EOF
  cat >"${MAILDIR}/.notmuch/hooks/post-new" <<EOF
#!/usr/bin/env bash
echo "post-new \$(notmuch count '*')" >>"${WORK}/hook.log"
EOF
  chmod +x "${MAILDIR}/.notmuch/hooks/post-new"

  # mbsync -q <channel>[:<box>]: moves remote/<channel>/<box>/* into the
  # maildir; a bare channel syncs every box. mbsync.fail holds a count of
  # calls left to fail.
  cat >"${WORK}/bin/mbsync" <<EOF
#!/usr/bin/env bash
target="\${@: -1}"
echo "\$(date +%s.%N) start \$target" >>"${WORK}/mbsync.log"
[[ -e "${WORK}/mbsync.running" ]] && echo OVERLAP >>"${WORK}/mbsync.log"
touch "${WORK}/mbsync.running"
sleep "\${STUB_MBSYNC_SLEEP:-0}"
rm -f "${WORK}/mbsync.running"
if [[ -s "${WORK}/mbsync.fail" ]]; then
  n=\$(cat "${WORK}/mbsync.fail")
  if ((n > 0)); then echo \$((n - 1)) >"${WORK}/mbsync.fail"; exit 1; fi
fi
chan="\${target%%:*}"
box=""
[[ "\$target" == *:* ]] && box="\${target#*:}"
for src in "${REMOTE}/\$chan"/*/ "${REMOTE}/\$chan"/*/*/; do
  [[ -d "\$src" ]] || continue
  b="\${src#"${REMOTE}/\$chan/"}"
  b="\${b%/}"
  [[ -z "\$box" || "\$b" == "\$box" ]] || continue
  for f in "\$src"*; do
    [[ -f "\$f" ]] || continue
    mkdir -p "${MAILDIR}/\$chan/\$b"/{cur,new,tmp}
    mv "\$f" "${MAILDIR}/\$chan/\$b/new/"
  done
done
exit 0
EOF
  # pgrep -x <name>: the display server always runs; any other name runs
  # while busy.<name> exists.
  cat >"${WORK}/bin/pgrep" <<EOF
#!/usr/bin/env bash
name="\${@: -1}"
[[ "\$name" == X* ]] && exit 0
[[ -e "${WORK}/busy.\$name" ]]
EOF
  cat >"${WORK}/bin/notify-send" <<EOF
#!/usr/bin/env bash
printf '%s|' "\$@" >>"${WORK}/popups.log"
echo >>"${WORK}/popups.log"
EOF
  # systemd-run: records one argument per line; fails while
  # systemd-run.fail exists, as a unit name already loaded does.
  cat >"${WORK}/bin/systemd-run" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "\$@" >>"${WORK}/systemd-run.log"
[[ ! -e "${WORK}/systemd-run.fail" ]]
EOF
  chmod +x "${WORK}/bin/"*
  export PATH="${WORK}/bin:${PATH}"

  export MAIL_SYNC_STATE="${WORK}/state"
  export MAIL_SYNC_LASTRUN="${WORK}/mailsynclastrun"
  export MAIL_SYNC_MAILDIR="$MAILDIR"
  unset MAILSYNC_MUTE MAIL_SYNC_DEFERRED
  N=0
  mkdir -p "${MAILDIR}/${ACCT}/INBOX"/{cur,new,tmp}
  notmuch new --quiet
  touch -d '-1 minute' "$MAIL_SYNC_LASTRUN"
  : >"${WORK}/hook.log"
}

teardown() {
  rm -rf "$WORK"
}

# remote <box> <id> <from> <subject>: one message waiting on the far side.
remote() {
  local box="$1" id="$2" from="$3" subject="$4"
  N=$((N + 1))
  mkdir -p "${REMOTE}/${ACCT}/${box}"
  printf 'From: %s\nTo: piotr.zaniewski@loft.sh\nSubject: %s\nMessage-ID: <%s@test>\nDate: %s\n\nbody\n' \
    "$from" "$subject" "$id" "$(date -R)" >"${REMOTE}/${ACCT}/${box}/${N}.${id}"
}

calls() {
  grep -v OVERLAP "${WORK}/mbsync.log" | sed 's/^[^ ]* start //'
}

popups() {
  if [[ -f "${WORK}/popups.log" ]]; then cat "${WORK}/popups.log"; fi
}

@test "new INBOX mail: scoped sync, one popup, indexed, hook ran" {
  remote INBOX a1 '"Alice Example" <alice@example.com>' "hello there"
  run "$SCRIPT" "$ACCT" INBOX "New Email"
  [ "$status" -eq 0 ]
  [ "$(calls)" = "${ACCT}:INBOX" ]
  [ "$(popups)" = "--app-name=mutt-wizard|📧Alice Example:|hello there|" ]
  [ "$(notmuch count id:a1@test)" -eq 1 ]
  [ "$(cat "${WORK}/hook.log")" = "post-new 1" ]
}

@test "a second event shows no popup for mail already announced" {
  remote INBOX a1 "alice@example.com" "hello"
  "$SCRIPT" "$ACCT" INBOX "New Email"
  run "$SCRIPT" "$ACCT" INBOX "New Email"
  [ "$status" -eq 0 ]
  [ "$(popups | wc -l)" -eq 1 ]
}

@test "the lastrun marker passes the new file, so mailsync does not repeat it" {
  remote INBOX a1 "alice@example.com" "hello"
  "$SCRIPT" "$ACCT" INBOX "New Email"
  run find "${MAILDIR}/${ACCT}/INBOX" -type f -newer "$MAIL_SYNC_LASTRUN"
  [ -z "$output" ]
}

@test "sent mail: syncs Sent then INBOX, no popup" {
  remote "[Gmail]/Sent Mail" s1 "piotr.zaniewski@loft.sh" "my reply"
  run "$SCRIPT" "$ACCT" "[Gmail]/Sent Mail" "New Email"
  [ "$status" -eq 0 ]
  [ "$(calls)" = "$(printf '%s\n%s' "${ACCT}:[Gmail]/Sent Mail" "${ACCT}:INBOX")" ]
  [ -z "$(popups)" ]
  [ "$(notmuch count id:s1@test)" -eq 1 ]
}

@test "an All Mail copy is never indexed before its INBOX copy" {
  remote "[Gmail]/All Mail" b1 "bob@example.com" "both places"
  remote INBOX b1 "bob@example.com" "both places"
  run "$SCRIPT" "$ACCT" "[Gmail]/All Mail" "New Email"
  [ "$status" -eq 0 ]
  [ "$(calls | tail -n1)" = "${ACCT}:INBOX" ]
  [ "$(cat "${WORK}/hook.log")" = "post-new 1" ]
  [ "$(notmuch search --output=files id:b1@test | wc -l)" -eq 2 ]
}

@test "connect event on INBOX syncs the whole account" {
  remote Archive c1 "carol@example.com" "while offline"
  run "$SCRIPT" "$ACCT" INBOX "Synchronize mailboxes without post-steps"
  [ "$status" -eq 0 ]
  [ "$(calls)" = "$ACCT" ]
  [ "$(notmuch count id:c1@test)" -eq 1 ]
}

@test "connect event on Sent stays scoped" {
  run "$SCRIPT" "$ACCT" "[Gmail]/Sent Mail" "Synchronize mailboxes without post-steps"
  [ "$status" -eq 0 ]
  [ "$(calls)" = "$(printf '%s\n%s' "${ACCT}:[Gmail]/Sent Mail" "${ACCT}:INBOX")" ]
}

@test "overlapping events never run mbsync at once" {
  export STUB_MBSYNC_SLEEP=1
  remote INBOX d1 "dan@example.com" "one"
  "$SCRIPT" "$ACCT" INBOX "New Email" >/dev/null &
  "$SCRIPT" "$ACCT" "[Gmail]/Sent Mail" "New Email" >/dev/null &
  "$SCRIPT" "$ACCT" INBOX "New Email" >/dev/null &
  wait
  run grep -c OVERLAP "${WORK}/mbsync.log"
  [ "$output" = "0" ]
  [ "$(calls | wc -l)" -eq 4 ]
  [ "$(popups | wc -l)" -eq 1 ]
}

@test "waits for an mbsync that runs without the lock" {
  touch "${WORK}/busy.mbsync"
  (sleep 2 && date +%s.%N >"${WORK}/freed" && rm -f "${WORK}/busy.mbsync") &
  run "$SCRIPT" "$ACCT" INBOX "New Email"
  wait
  [ "$status" -eq 0 ]
  [[ "$output" == *"waiting for mbsync to finish"* ]]
  started="$(awk 'NR == 1 {print $1}' "${WORK}/mbsync.log")"
  awk -v s="$started" -v f="$(cat "${WORK}/freed")" 'BEGIN {exit !(s >= f)}'
}

@test "waits for mailsync too" {
  touch "${WORK}/busy.mailsync"
  (sleep 1 && rm -f "${WORK}/busy.mailsync") &
  run "$SCRIPT" "$ACCT" INBOX "New Email"
  wait
  [ "$status" -eq 0 ]
  [[ "$output" == *"waiting for mailsync to finish"* ]]
}

@test "a failed mbsync is retried once" {
  echo 1 >"${WORK}/mbsync.fail"
  remote INBOX e1 "eve@example.com" "retry me"
  run "$SCRIPT" "$ACCT" INBOX "New Email"
  [ "$status" -eq 0 ]
  [[ "$output" == *"retrying"* ]]
  [ "$(calls | wc -l)" -eq 2 ]
  [ "$(notmuch count id:e1@test)" -eq 1 ]
  [ ! -e "${WORK}/systemd-run.log" ]
}

@test "mbsync failing twice exits 1 and still indexes what is there" {
  echo 2 >"${WORK}/mbsync.fail"
  run "$SCRIPT" "$ACCT" INBOX "New Email"
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed twice"* ]]
  [ "$(cat "${WORK}/hook.log")" = "post-new 0" ]
}

@test "mbsync failing twice schedules one deferred run of the same event" {
  echo 2 >"${WORK}/mbsync.fail"
  run "$SCRIPT" "$ACCT" "[Gmail]/Sent Mail" "New Email"
  [ "$status" -eq 1 ]
  [[ "$output" == *"retry scheduled in 60s"* ]]
  log="$(cat "${WORK}/systemd-run.log")"
  grep -qx -- '--user' <<<"$log"
  grep -qx -- '--collect' <<<"$log"
  grep -qx -- '--on-active=60' <<<"$log"
  grep -qx -- '--timer-property=AccuracySec=1s' <<<"$log"
  grep -qx -- '--setenv=MAIL_SYNC_DEFERRED=1' <<<"$log"
  grep -qFx -- "--setenv=NOTMUCH_CONFIG=${NOTMUCH_CONFIG}" <<<"$log"
  grep -qFx -- "--setenv=MAIL_SYNC_STATE=${MAIL_SYNC_STATE}" <<<"$log"
  grep -qFx -- "--setenv=MAIL_SYNC_MAILDIR=${MAILDIR}" <<<"$log"
  grep -qFx -- "--unit=mail-idle-retry-$(systemd-escape "${ACCT}-[Gmail]/Sent Mail")" <<<"$log"
  [ "$(tail -n 4 <<<"$log")" = "$(printf '%s\n' "$(readlink -f "$SCRIPT")" "$ACCT" "[Gmail]/Sent Mail" "New Email")" ]
}

@test "a deferred run that fails again schedules nothing" {
  export MAIL_SYNC_DEFERRED=1
  echo 2 >"${WORK}/mbsync.fail"
  run "$SCRIPT" "$ACCT" INBOX "New Email"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no further retry"* ]]
  [ ! -e "${WORK}/systemd-run.log" ]
}

@test "a retry already pending for the box leaves the run's result alone" {
  touch "${WORK}/systemd-run.fail"
  echo 2 >"${WORK}/mbsync.fail"
  run "$SCRIPT" "$ACCT" INBOX "New Email"
  [ "$status" -eq 1 ]
  [[ "$output" == *"retry not scheduled"* ]]
  [ "$(cat "${WORK}/hook.log")" = "post-new 0" ]
}

@test "a failed notmuch new schedules no mbsync retry" {
  printf '#!/usr/bin/env bash\nexit 1\n' >"${WORK}/bin/notmuch"
  chmod +x "${WORK}/bin/notmuch"
  run "$SCRIPT" "$ACCT" INBOX "New Email"
  [ "$status" -eq 1 ]
  [ ! -e "${WORK}/systemd-run.log" ]
}

@test "more than five new mails make one summary popup" {
  for i in 1 2 3 4 5 6; do remote INBOX "m$i" "x@example.com" "s$i"; done
  run "$SCRIPT" "$ACCT" INBOX "New Email"
  [ "$status" -eq 0 ]
  [ "$(popups)" = "--app-name=mutt-wizard|New Mail!|📬 6 new mail(s) in \`${ACCT}\` account.|" ]
}

@test "MIME encoded headers are decoded in the popup" {
  remote INBOX f1 "=?UTF-8?B?WsOzZmlh?= <zofia@example.com>" "=?UTF-8?Q?Cze=C5=9B=C4=87?="
  run "$SCRIPT" "$ACCT" INBOX "New Email"
  [ "$(popups)" = "--app-name=mutt-wizard|📧Zófia:|Cześć|" ]
}

@test "MAILSYNC_MUTE silences popups" {
  export MAILSYNC_MUTE=1
  remote INBOX g1 "gus@example.com" "quiet"
  run "$SCRIPT" "$ACCT" INBOX "New Email"
  [ "$status" -eq 0 ]
  [ -z "$(popups)" ]
}

@test "missing arguments print usage" {
  run "$SCRIPT" "$ACCT"
  [ "$status" -eq 1 ]
  [[ "$output" == *usage* ]]
}
