#!/usr/bin/env bats

# __notmuch_post_new.sh against a throwaway notmuch database, never the live
# one. The hook is linked into the temp database's hooks dir and fired by a
# real `notmuch new`, the path mailsync takes. A stub thread-watch records how
# it was called.

setup() {
  HOOK="${BATS_TEST_DIRNAME}/../../scripts/__notmuch_post_new.sh"
  WORK="$(mktemp -d)"
  MAILDIR="${WORK}/mail"
  mkdir -p "${MAILDIR}/.notmuch/hooks" "${WORK}/bin"
  ln -s "$HOOK" "${MAILDIR}/.notmuch/hooks/post-new"

  export NOTMUCH_CONFIG="${WORK}/notmuch-config"
  cat >"$NOTMUCH_CONFIG" <<EOF
[database]
path=${MAILDIR}
[user]
name=piotrzan
primary_email=piotrzan@gmail.com
other_email=piotr.zaniewski@loft.sh;piotr.zaniewski@vcluster.com
[new]
tags=unread;inbox;
[search]
exclude_tags=deleted;spam;
[maildir]
synchronize_flags=true
EOF

  export MAIL_EVENTS_STATE="${WORK}/state"
  export MAIL_EVENTS_LOG="${WORK}/notifications.log"
  export MAIL_EVENTS_THREAD_WATCH="${WORK}/bin/thread-watch"
  cat >"$MAIL_EVENTS_THREAD_WATCH" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"${WORK}/thread-watch.log"
[[ -e "${WORK}/thread-watch.fail" ]] && { echo "boom"; exit 1; }
exit 0
EOF
  chmod +x "$MAIL_EVENTS_THREAD_WATCH"

  WORK_INBOX="piotr.zaniewski@loft.sh/INBOX"
  N=0
  # An old mail, so the database exists before the first run seeds.
  deliver "$WORK_INBOX" old "Alice <alice@example.com>" "piotr.zaniewski@loft.sh" "old news"
  notmuch new --quiet
}

teardown() {
  rm -rf "$WORK"
}

# deliver <folder> <id> <from> <to> <subject> [extra header]...: writes one
# message into new/. The id doubles as the Message-ID local part.
deliver() {
  local folder="$1" id="$2" from="$3" to="$4" subject="$5"
  shift 5
  local mid="${id}@test"
  [[ "$id" == *@* ]] && { mid="$id"; id="${id%%@*}"; }
  N=$((N + 1))
  mkdir -p "${MAILDIR}/${folder}"/{cur,new,tmp}
  {
    printf 'From: %s\nTo: %s\nSubject: %s\n' "$from" "$to" "$subject"
    printf 'Message-ID: <%s>\nDate: %s\n' "$mid" "$(date -R -d "-$((100 - N)) minutes")"
    [[ $# -gt 0 ]] && printf '%s\n' "$@"
    printf '\nbody of %s\n' "$id"
  } >"${MAILDIR}/${folder}/new/${N}.${id}.test"
}

records() {
  if [[ -f "$MAIL_EVENTS_LOG" ]]; then cat "$MAIL_EVENTS_LOG"; fi
}

record_count() {
  records | grep -c . || true
}

tags_of() {
  notmuch search --output=tags "id:$1@test" | grep '^waiting/' | tr '\n' ' ' || true
}

@test "the first run seeds silently: existing mail fires nothing" {
  rm -rf "$MAIL_EVENTS_STATE"
  run "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(record_count)" -eq 0 ]
  [ -s "${MAIL_EVENTS_STATE}/seen" ]
  grep -q 'old@test' "${MAIL_EVENTS_STATE}/seen"
  [ -s "${MAIL_EVENTS_STATE}/revision" ]
}

@test "a new direct mail is one 4-field record with metadata before the subject" {
  deliver "$WORK_INBOX" m1 "\"Smith, Dan\" <Dan.Smith@mend.io>" "Piotr Zaniewski <piotr.zaniewski@vcluster.com>" "Mend terms and DPA for review" \
    "Cc: josh@mend.io"
  notmuch new --quiet

  [ "$(record_count)" -eq 1 ]
  line="$(records)"
  [ "$(awk -F'\t' '{print NF}' <<<"$line")" -eq 4 ]
  [[ "$line" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$'\t'mail$'\t'📧Smith,\ Dan:$'\t' ]]
  tid="$(notmuch search --output=threads id:m1@test)"
  body="$(cut -f4 <<<"$line")"
  [ "$body" = "${tid} to:direct bulk:- account:piotr.zaniewski@loft.sh from:dan.smith@mend.io | Mend terms and DPA for review" ]
}

@test "a second run, and reading the mail, fire nothing more" {
  deliver "$WORK_INBOX" m1 "Dan <dan@mend.io>" "piotr.zaniewski@loft.sh" "terms"
  notmuch new --quiet
  notmuch new --quiet
  notmuch tag -unread -- id:m1@test
  notmuch tag -unread -- id:old@test
  notmuch new --quiet

  [ "$(record_count)" -eq 1 ]
}

@test "a gmail copy in All Mail is the same message, one record" {
  deliver "$WORK_INBOX" dup "Dan <dan@mend.io>" "piotr.zaniewski@loft.sh" "twice"
  deliver "piotr.zaniewski@loft.sh/[Gmail]/All Mail" dup "Dan <dan@mend.io>" "piotr.zaniewski@loft.sh" "twice"
  notmuch new --quiet

  [ "$(record_count)" -eq 1 ]
}

@test "Piotr's own mail, from any of his addresses, fires nothing" {
  deliver "$WORK_INBOX" self1 "Piotr Zaniewski <piotr.zaniewski@vcluster.com>" "dan@mend.io" "from the alias"
  deliver "piotrzan@gmail.com/INBOX" self2 "piotrzan@gmail.com" "piotrzan@gmail.com" "[kctx AUTH] code"
  notmuch new --quiet

  [ "$(record_count)" -eq 0 ]
}

@test "mail outside INBOX fires nothing" {
  deliver "piotrzan@gmail.com/1. Newsletters" nl "News <news@example.com>" "piotrzan@gmail.com" "weekly"
  notmuch new --quiet

  [ "$(record_count)" -eq 0 ]
}

@test "cc only, no address of Piotr's, and bulk signals are named" {
  deliver "$WORK_INBOX" cc1 "Ann <ann@example.com>" "bob@example.com" "fyi" "Cc: Piotr <PIOTR.ZANIEWSKI@loft.sh>"
  deliver "$WORK_INBOX" none1 "Ann <ann@example.com>" "team@loft.sh" "to the group"
  deliver "$WORK_INBOX" bulk1 "Shop <no-reply@shop.example>" "piotr.zaniewski@loft.sh" "sale" \
    "List-Id: <deals.shop.example>" "Precedence: bulk" "List-Unsubscribe:" " <https://shop.example/u>" "Auto-Submitted: auto-generated"
  notmuch new --quiet

  [ "$(record_count)" -eq 3 ]
  grep -q 'to:cc bulk:- ' "$MAIL_EVENTS_LOG"
  grep -q 'to:none bulk:- ' "$MAIL_EVENTS_LOG"
  grep -q 'to:direct bulk:list-id,list-unsubscribe,precedence,auto-submitted,noreply ' "$MAIL_EVENTS_LOG"
}

@test "mailing services, calendar notices and shared addresses are bulk; a person on gmail is not" {
  deliver "$WORK_INBOX" "ses@eu-west-1.amazonses.com" "Amazon.de <versandbestaetigung@amazon.de>" "piotrzan@gmail.com" "Dispatched"
  deliver "$WORK_INBOX" sg "DigitalOcean <support@digitalocean.com>" "piotr.zaniewski@loft.sh" "ticket" "X-SG-EID: abc"
  deliver "$WORK_INBOX" fb "Tailscale <kelsea@tailscale.com>" "piotr.zaniewski@loft.sh" "renewal" "Feedback-ID: 1:2:3"
  deliver "$WORK_INBOX" cal "Jake <jake@sentinelone.com>" "piotr.zaniewski@loft.sh" "Invitation: review" \
    "Sender: Google Calendar <calendar-notification@google.com>"
  deliver "$WORK_INBOX" pp "PayPal <service@paypal.de>" "piotrzan@gmail.com" "Receipt"
  deliver "$WORK_INBOX" nr "Apple <no_reply@email.apple.com>" "piotrzan@gmail.com" "Your receipt"
  deliver "$WORK_INBOX" "CAH8wpK@mail.gmail.com" "Dan <dan@mend.io>" "piotr.zaniewski@loft.sh" "terms" "X-Gm-Message-State: x"
  notmuch new --quiet

  grep -q 'from:versandbestaetigung@amazon.de | Dispatched' <(grep 'bulk:esp ' "$MAIL_EVENTS_LOG")
  grep -q 'bulk:esp,role account:.* from:support@digitalocean.com' "$MAIL_EVENTS_LOG"
  grep -q 'bulk:esp account:.* from:kelsea@tailscale.com' "$MAIL_EVENTS_LOG"
  grep -q 'bulk:calendar account:.* from:jake@sentinelone.com' "$MAIL_EVENTS_LOG"
  grep -q 'bulk:role account:.* from:service@paypal.de' "$MAIL_EVENTS_LOG"
  grep -q 'bulk:noreply account:.* from:no_reply@email.apple.com' "$MAIL_EVENTS_LOG"
  grep -q 'bulk:- account:.* from:dan@mend.io' "$MAIL_EVENTS_LOG"
  [ "$(notmuch count --output=threads tag:waiting/me)" -eq 1 ]
  [ "$(notmuch search --output=messages tag:waiting/me)" = "id:CAH8wpK@mail.gmail.com" ]
}

@test "Auto-Submitted: no is not a bulk signal" {
  deliver "$WORK_INBOX" human "Ann <ann@example.com>" "piotr.zaniewski@loft.sh" "hi" "Auto-Submitted: no"
  notmuch new --quiet

  grep -q 'to:direct bulk:- ' "$MAIL_EVENTS_LOG"
}

@test "an outsider addressing Piotr directly sets waiting/me on the whole thread" {
  deliver "$WORK_INBOX" w1 "Dan <dan@mend.io>" "piotr.zaniewski@vcluster.com" "terms"
  notmuch new --quiet

  [ "$(tags_of w1)" = "waiting/me " ]
}

@test "Piotr's reply clears waiting/me and sets waiting/them, the next outsider reply flips it back" {
  deliver "$WORK_INBOX" w1 "Dan <dan@mend.io>" "piotr.zaniewski@vcluster.com" "terms"
  notmuch new --quiet
  deliver "piotr.zaniewski@loft.sh/[Gmail]/Sent Mail" w2 "Piotr Zaniewski <piotr.zaniewski@vcluster.com>" "dan@mend.io" "Re: terms" \
    "In-Reply-To: <w1@test>" "References: <w1@test>"
  notmuch new --quiet

  [ "$(tags_of w1)" = "waiting/them " ]
  [ "$(tags_of w2)" = "waiting/them " ]

  deliver "$WORK_INBOX" w3 "Dan <dan@mend.io>" "piotr.zaniewski@vcluster.com" "Re: terms" \
    "In-Reply-To: <w2@test>" "References: <w1@test> <w2@test>"
  notmuch new --quiet

  [ "$(tags_of w1)" = "waiting/me " ]
}

@test "mail Piotr sends only to himself waits on nobody" {
  deliver "piotrzan@gmail.com/[Gmail]/Sent Mail" note "piotrzan@gmail.com" "piotrzan@gmail.com" "[kctx AUTH] login" "Cc: piotr.zaniewski@loft.sh"
  deliver "piotrzan@gmail.com/[Gmail]/Sent Mail" fwd "piotrzan@gmail.com" "daniel@vcluster.com" "Fwd: renewal" "Cc: piotr.zaniewski@loft.sh"
  notmuch new --quiet

  [ -z "$(tags_of note)" ]
  [ "$(tags_of fwd)" = "waiting/them " ]
}

@test "a draft or a trashed mail from Piotr does not answer the thread" {
  deliver "$WORK_INBOX" d1 "Dan <dan@mend.io>" "piotr.zaniewski@loft.sh" "question"
  notmuch new --quiet
  deliver "piotr.zaniewski@loft.sh/[Gmail]/Drafts" d2 "Piotr Zaniewski <piotr.zaniewski@loft.sh>" "dan@mend.io" "Re: question" \
    "In-Reply-To: <d1@test>" "References: <d1@test>"
  deliver "piotr.zaniewski@loft.sh/[Gmail]/Trash" d3 "Piotr Zaniewski <piotr.zaniewski@loft.sh>" "dan@mend.io" "Re: question" \
    "In-Reply-To: <d1@test>" "References: <d1@test>"
  notmuch new --quiet

  [ "$(tags_of d1)" = "waiting/me " ]
}

@test "cc only, bulk, or noreply mail does not set waiting/me" {
  deliver "$WORK_INBOX" c1 "Ann <ann@example.com>" "bob@example.com" "fyi" "Cc: piotr.zaniewski@loft.sh"
  deliver "$WORK_INBOX" b1 "List <list@example.com>" "piotr.zaniewski@loft.sh" "digest" "List-Id: <x.example.com>"
  deliver "$WORK_INBOX" n1 "Bot <noreply@example.com>" "piotr.zaniewski@loft.sh" "receipt"
  notmuch new --quiet

  [ -z "$(tags_of c1)" ]
  [ -z "$(tags_of b1)" ]
  [ -z "$(tags_of n1)" ]
}

@test "backfill recomputes threads in the window and lists waiting/me" {
  notmuch new --quiet --no-hooks
  deliver "$WORK_INBOX" bf1 "Kelsea <kelsea@tailscale.com>" "piotr.zaniewski@vcluster.com" "Tailscale renewal"
  deliver "$WORK_INBOX" bf2 "Ann <ann@example.com>" "piotr.zaniewski@loft.sh" "lunch?"
  notmuch new --quiet --no-hooks
  deliver "piotr.zaniewski@loft.sh/[Gmail]/Sent Mail" bf3 "piotr.zaniewski@loft.sh" "ann@example.com" "Re: lunch?" \
    "In-Reply-To: <bf2@test>" "References: <bf2@test>"
  notmuch new --quiet --no-hooks
  [ -z "$(tags_of bf1)" ]

  run "$HOOK" --backfill 30
  [ "$status" -eq 0 ]
  [[ "$output" == *"Tailscale renewal"* ]]
  [[ "$output" != *"lunch"* ]]
  [ "$(tags_of bf1)" = "waiting/me " ]
  [ "$(tags_of bf2)" = "waiting/them " ]
}

@test "every run checks the mail thread-watch subscriptions" {
  deliver "$WORK_INBOX" t1 "Dan <dan@mend.io>" "piotr.zaniewski@loft.sh" "x"
  notmuch new --quiet

  grep -qx 'check-source mail' "${WORK}/thread-watch.log"
  [ "$(grep -c . "${WORK}/thread-watch.log")" -eq 2 ]
}

@test "a thread-watch failure becomes one error record and a failing hook" {
  touch "${WORK}/thread-watch.fail"
  run "$HOOK"
  [ "$status" -eq 1 ]
  grep -q $'\tmail\tmail hook error:\tthread-watch check-source mail: boom' "$MAIL_EVENTS_LOG"
}

@test "a rebuilt database reseeds instead of firing its whole history" {
  echo "another-uuid 5" >"${MAIL_EVENTS_STATE}/revision"
  deliver "$WORK_INBOX" r1 "Dan <dan@mend.io>" "piotr.zaniewski@loft.sh" "x"
  notmuch new --quiet

  [ "$(record_count)" -eq 0 ]
  grep -q 'r1@test' "${MAIL_EVENTS_STATE}/seen"
}
