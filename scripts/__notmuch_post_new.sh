#!/usr/bin/env bash
# PROJECT: mail-attention
# notmuch post-new hook. Turns each new mail into one structured event for
# Kendra (Gordon while she is down) and keeps two waiting tags current on
# every thread it touches.
#
# Linked as notmuch/hooks/post-new, the hook_dir in the tracked .notmuch-config,
# so it runs after every `notmuch new`: __mail_idle_sync.sh on each IMAP IDLE
# event (goimapnotify.service), the mailsync backstop every 2 hours, or a run
# by hand.
#
# Events. A message is new when its lastmod is past the last run's revision and
# its id is not in the seen set. Lastmod alone is not enough, because reading
# or tagging a mail moves its lastmod too. The seen set is seeded on the first
# run, so history never fires. Every new message from someone other than
# Piotr yields one record on first sight, whatever folder its files sit in:
# INBOX, a Gmail label that skips the inbox, Spam, Trash or All Mail alone.
# Filtering is notify-watch's ignore.txt, never this hook. The record goes to
# notifications.log, the file notify-watch follows with a byte cursor. The
# event therefore waits there while Kendra and Gordon are down, and no second
# desktop popup appears:
#
#   <date time>\tmail\t📧<name>:\tthread:<id> to:<direct|cc|none> bulk:<signals|-> account:<acct> folder:<folder> from:<addr> [svc:<service>] | <subject>
#
# svc names the tool a notification mail comes from (gdocs, gdrive, figma,
# zoom, reclaim, ramp, notion), so Kendra routes it as that source's event
# and __intake_source_health.sh shows its last record. Other mail has no svc.
#
# folder is the message's best home: inbox when any file sits in INBOX, else
# spam or trash, else its label, else a Gmail system folder (important), else
# all-mail. It is lowercased, with every run of other characters turned into
# one "-" ("4. Amazon" is 4-amazon), so the record stays space-free before
# " | ". __mail_idle_sync.sh syncs INBOX last, so an inbox mail's INBOX copy is
# indexed with its All Mail copy; loft.sh label mail, whose label folder only
# the two-hourly full sync fetches, is all-mail.
#
# The summary matches the mutt-wizard popup's "📧<name>:", so ignore.txt sender
# rules carry over. Metadata leads the body so notify-watch's 300 character cut
# never drops the thread id. Each record is one write() well under 4 KB, so it
# cannot interleave with notification-logger.service's own appends.
#
# Waiting tags. For each thread with a message touched since the last run and
# dated within MAIL_EVENTS_DAYS, the latest live message decides:
#   waiting/them  it is from Piotr and to someone else
#   waiting/me    it is from someone else, Piotr is in To, and it carries no
#                 bulk signal
#   neither       anything else
#
# Bulk signals mark mail no person wrote to Piotr: list-id, list-unsubscribe,
# precedence (bulk, list, junk), auto-submitted, esp (a mailing service's
# header or Message-ID domain, e.g. Feedback-ID, SendGrid, Amazon SES),
# calendar (a Google Calendar notification), noreply, and role (a shared
# address such as service@, support@, order@, info@). Measured on the live
# database: without esp, calendar and role, 162 of 171 waiting/me threads were
# Amazon, PayPal, SendGrid and similar notifications.
# Drafts, and messages whose every file sits in Drafts, Trash or Spam, do not
# count. Piotr's addresses are notmuch's user.primary_email and
# user.other_email.
#
# Gordon owns a third tag, gordon/cleared, set on a thread after Gordon has
# processed it so the morning sweep (tag:waiting/me and not tag:gordon/cleared)
# stops surfacing it. The hook removes it from every thread that receives a new
# message, from anyone, so a fresh reply re-arms the sweep. New means an id
# outside the seen set, not a lastmod bump: tagging or reading a mail moves its
# lastmod too and must not undo the clearing. waiting/* is untouched by it.
#
# Then every mail thread-watch subscription is checked
# (`__thread_watch.sh check-source mail`).
#
# A failure writes one "mail hook error" record to the same log, so Gordon
# hears about it, and exits 1.
#
# Usage:
#   __notmuch_post_new.sh                    the hook
#   __notmuch_post_new.sh --backfill <days>  recompute the waiting tags for
#                                            threads with mail in the last
#                                            <days>, then list tag:waiting/me
#
# Env: MAIL_EVENTS_STATE (state dir), MAIL_EVENTS_LOG (event log),
# MAIL_EVENTS_THREAD_WATCH (thread-watch script, skipped when not executable),
# MAIL_EVENTS_HANDOFF_CHECK (Gordon's board check, skipped when not executable),
# MAIL_EVENTS_HANDOFF_TIMEOUT (seconds it may take, default 20),
# MAIL_EVENTS_DAYS (event and touch window, default 30), MAIL_EVENTS_SEEN_DAYS
# (how long a seen id is kept, default 60). NOTMUCH_CONFIG picks the database.
set -eo pipefail

# cron runs with PATH=/usr/bin:/bin.
PATH="${PATH}:/usr/local/bin"

STATE_DIR="${MAIL_EVENTS_STATE:-$HOME/.local/state/mail-events}"
EVENT_LOG="${MAIL_EVENTS_LOG:-$HOME/.local/state/notifications.log}"
THREAD_WATCH="${MAIL_EVENTS_THREAD_WATCH:-$HOME/.claude/scripts/__thread_watch.sh}"
HANDOFF_CHECK="${MAIL_EVENTS_HANDOFF_CHECK:-$HOME/.claude/scripts/__gordon_board_check.sh}"
DAYS="${MAIL_EVENTS_DAYS:-30}"
SEEN_DAYS="${MAIL_EVENTS_SEEN_DAYS:-60}"
SELF_ADDRS=""

# Flattens notmuch show JSON to one object per message.
# shellcheck disable=SC2016 # jq program, not shell
JQ_MESSAGES='.. | objects | select(has("headers"))'
# A live message: not a draft, deleted or spam, and with a file outside
# Drafts, Trash and Spam.
JQ_LIVE='select(((.tags | index("draft")) or (.tags | index("deleted")) or (.tags | index("spam"))) | not)
    | select(any(.filename[]; test("/(Drafts|Trash|Spam)/(cur|new|tmp)/[^/]*$") | not))'

clean() {
    local s="${1//$'\t'/ }"
    s="${s//$'\r'/ }"
    printf '%s' "${s//$'\n'/ }"
}

# append_record <summary> <body>: one record, one write().
append_record() {
    local line
    line="$(printf '%s\tmail\t%s\t%s' "$(date '+%Y-%m-%d %H:%M:%S')" "$(clean "$1")" "$(clean "$2")")"
    line="${line:0:1000}"
    mkdir -p "$(dirname "$EVENT_LOG")"
    printf '%s\n' "$line" >>"$EVENT_LOG"
}

fail() {
    append_record "mail hook error:" "$* (dotfiles scripts/__notmuch_post_new.sh)" || true
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

load_self() {
    SELF_ADDRS="$({
        notmuch config get user.primary_email
        notmuch config get user.other_email
    } 2>/dev/null | tr '[:upper:];' '[:lower:]\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; /^$/d' | sort -u)"
    [[ -n "$SELF_ADDRS" ]] || fail "notmuch config has no user.primary_email"
}

# Every address in a header, lowercased, one per line.
addrs_of() {
    grep -oE '[A-Za-z0-9._%+=-]+@[A-Za-z0-9.-]+' <<<"$1" | tr '[:upper:]' '[:lower:]' || true
}

has_self() {
    [[ -n "$1" ]] && addrs_of "$1" | grep -qxF -f <(printf '%s\n' "$SELF_ADDRS")
}

# has_other <header>: true when it names an address that is not Piotr's.
has_other() {
    addrs_of "$1" | grep -qvxF -f <(printf '%s\n' "$SELF_ADDRS")
}

is_self() {
    grep -qxF -- "${1,,}" <<<"$SELF_ADDRS"
}

# addressing <To> <Cc>: direct when Piotr is in To, cc when only in Cc.
addressing() {
    if has_self "$1"; then
        echo direct
    elif has_self "$2"; then
        echo cc
    else
        echo none
    fi
}

# split_from <From>: sets from_name and from_addr. The name follows mailsync's
# popup (the display name without quotes, else the address), so ignore.txt
# sender rules match both.
split_from() {
    local f="$1"
    if [[ "$f" =~ ^(.*)\<([^\>]+)\>[[:space:]]*$ ]]; then
        from_name="${BASH_REMATCH[1]}"
        from_addr="${BASH_REMATCH[2]}"
    else
        from_name=""
        from_addr="$f"
    fi
    from_name="$(sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//' <<<"$from_name")"
    from_addr="$(tr -d '[:space:]' <<<"${from_addr,,}")"
    [[ -n "$from_name" ]] || from_name="$from_addr"
}

# Mailing services, by header and by Message-ID domain.
ESP_HEADERS='^(feedback-id|x-ses-outgoing|x-sg-eid|x-pm-message-id|x-mailgun-[a-z-]+|x-mc-user|x-mandrill-[a-z-]+|x-hs-cid|x-campaign[a-z-]*|x-csa-complaints|x-sfmc-[a-z-]+):'
ESP_MSGID='^message-id:.*@([a-z0-9.-]+\.)?(amazonses\.com|mailersend\.net|mtasv\.net|sendgrid\.net|mailgun\.(org|net)|mcsv\.net|mandrillapp\.com|amplemarket\.com|hubspotemail\.net)>'
# Shared addresses no single person answers from.
ROLE_LOCAL='^(service|support|order|orders|shop|onlineshop|servicecenter|info|hello|hi|communications|newsletter|newsletters|news|notification|notifications|notify|alert|alerts|billing|invoice|invoices|receipt|receipts|account|accounts|marketing|team|cs|careers|jobs|events|feedback|admin|security|postmaster|bounce|bounces)$'

# bulk_of <file> <from address>: the bulk signals, comma joined, or -.
bulk_of() {
    local file="$1" head="" local_part="${2%%@*}"
    local -a sig=()
    if [[ -r "$file" ]]; then
        # The header block with folded lines joined.
        head="$(awk '/^\r?$/ {exit} /^[ \t]/ {sub(/^[ \t]+/, " "); h = h $0; next} {if (h != "") print h; h = $0} END {if (h != "") print h}' "$file" | tr -d '\r')"
    fi
    grep -qi '^list-id:' <<<"$head" && sig+=(list-id)
    grep -qi '^list-unsubscribe:' <<<"$head" && sig+=(list-unsubscribe)
    grep -qiE '^precedence:[[:space:]]*(bulk|list|junk)' <<<"$head" && sig+=(precedence)
    if grep -qi '^auto-submitted:' <<<"$head" && ! grep -qiE '^auto-submitted:[[:space:]]*no[[:space:]]*$' <<<"$head"; then
        sig+=(auto-submitted)
    fi
    if grep -qiE "$ESP_HEADERS" <<<"$head" || grep -qiE "$ESP_MSGID" <<<"$head"; then
        sig+=(esp)
    fi
    grep -qiE '^(sender:.*calendar-notification@google\.com|x-google-calendar-notification:)' <<<"$head" && sig+=(calendar)
    [[ "$local_part" =~ (^|[._+-])(no[._-]?reply|do[._-]?not[._-]?reply|mailer-daemon)([._+-]|$) ]] && sig+=(noreply)
    [[ "$local_part" =~ $ROLE_LOCAL ]] && sig+=(role)
    if ((${#sig[@]} == 0)); then
        echo -
    else
        local IFS=,
        echo "${sig[*]}"
    fi
}

# The best home of a message, from notmuch show JSON, as "<account>\t<folder>";
# see the folder field above. $root is the database path with a trailing /.
# shellcheck disable=SC2016 # jq program, not shell
JQ_HOME='[.filename[] | ltrimstr($root) | capture("^(?<acct>[^/]+)/(?<box>.+)/(cur|new|tmp)/[^/]*$")]
    | map(. + {rank: (if .box == "INBOX" then 0
        elif .box == "[Gmail]/Spam" or .box == "[Gmail]/Trash" then 1
        elif .box == "[Gmail]/All Mail" then 4
        elif (.box | startswith("[Gmail]/")) then 3
        else 2 end)})
    | sort_by(.rank, .box) | first // empty
    | (.box | ltrimstr("[Gmail]/") | ascii_downcase | gsub("[^a-z0-9]+"; "-") | ltrimstr("-") | rtrimstr("-")) as $f
    | "\(.acct)\t\(if $f == "" then "other" else $f end)"'

# id_query <message id>: a notmuch term for it, quoted.
id_query() {
    printf 'id:"%s"' "${1//\"/\"\"}"
}

# svc_of <from address>: the tool a notification mail comes from, or nothing.
# Senders measured on the live database (365 days, 23 Oct 2026).
svc_of() {
    case "$1" in
        comments-noreply@docs.google.com) echo gdocs ;;
        drive-shares-dm-noreply@google.com | drive-shares-noreply@google.com) echo gdrive ;;
        *@figma.com | *.figma.com) echo figma ;;
        *@zoom.us | *.zoom.us) echo zoom ;;
        *@reclaim.ai) echo reclaim ;;
        *@ramp.com) echo ramp ;;
        *@notion.so | *.notion.so | *@makenotion.com) echo notion ;;
    esac
}

# event_for <message id>: appends the record for one new message, unless it
# is Piotr's own.
event_for() {
    local id="$1" msg tid file home account folder addressed bulk subject dbpath svc
    msg="$(notmuch show --format=json --body=false --entire-thread=false "$(id_query "$id")" |
        jq -c "[$JQ_MESSAGES | select(.match)][0] // empty")"
    [[ -n "$msg" ]] || return 0
    split_from "$(jq -r '.headers.From // ""' <<<"$msg")"
    is_self "$from_addr" && return 0
    dbpath="$(notmuch config get database.path)"
    home="$(jq -r --arg root "${dbpath%/}/" "$JQ_HOME" <<<"$msg")"
    account="${home%%$'\t'*}"
    folder="${home#*$'\t'}"
    [[ -n "$home" ]] || account=unknown folder=unknown
    tid="$(notmuch search --output=threads "$(id_query "$id")" | head -n1)"
    tid="${tid#thread:}"
    addressed="$(addressing "$(jq -r '.headers.To // ""' <<<"$msg")" "$(jq -r '.headers.Cc // ""' <<<"$msg")")"
    file="$(jq -r '.filename[0]' <<<"$msg")"
    bulk="$(bulk_of "$file" "$from_addr")"
    subject="$(jq -r '.headers.Subject // ""' <<<"$msg")"
    svc="$(svc_of "$from_addr")"
    append_record "📧${from_name:0:80}:" \
        "thread:${tid} to:${addressed} bulk:${bulk} account:${account} folder:${folder} from:${from_addr}${svc:+ svc:$svc} | ${subject:0:200}"
}

# waiting_ops <thread id>: prints the notmuch tag batch lines that bring the
# thread's waiting tags to what its latest live message says.
waiting_ops() {
    local tid="$1" latest want
    latest="$(notmuch show --format=json --body=false --entire-thread=true "thread:$tid" |
        jq -c "[$JQ_MESSAGES | $JQ_LIVE] | max_by(.timestamp) // empty")"
    want=none
    if [[ -n "$latest" ]]; then
        split_from "$(jq -r '.headers.From // ""' <<<"$latest")"
        if is_self "$from_addr"; then
            # Mail Piotr sends only to himself waits on nobody.
            has_other "$(jq -r '(.headers.To // "") + ", " + (.headers.Cc // "")' <<<"$latest")" && want=them
        elif [[ "$(addressing "$(jq -r '.headers.To // ""' <<<"$latest")" "")" == direct &&
            "$(bulk_of "$(jq -r '.filename[0]' <<<"$latest")" "$from_addr")" == - ]]; then
            want=me
        fi
    fi
    case "$want" in
    me)
        printf '+waiting/me -- thread:%s and not tag:waiting/me\n' "$tid"
        printf -- '-waiting/them -- thread:%s and tag:waiting/them\n' "$tid"
        ;;
    them)
        printf '+waiting/them -- thread:%s and not tag:waiting/them\n' "$tid"
        printf -- '-waiting/me -- thread:%s and tag:waiting/me\n' "$tid"
        ;;
    *)
        printf -- '-waiting/me -- thread:%s and tag:waiting/me\n' "$tid"
        printf -- '-waiting/them -- thread:%s and tag:waiting/them\n' "$tid"
        ;;
    esac
}

# rearm <message id>...: removes gordon/cleared from the thread of each new
# message, in one batch.
rearm() {
    local id tid ops=""
    for id in "$@"; do
        tid="$(notmuch search --output=threads "$(id_query "$id")" | head -n1)"
        [[ -n "$tid" ]] || continue
        ops+="-gordon/cleared -- $tid and tag:gordon/cleared"$'\n'
    done
    [[ -n "${ops//$'\n'/}" ]] || return 0
    notmuch tag --batch <<<"$ops"
}

# recompute <thread id>...: applies waiting_ops for each thread in one batch.
recompute() {
    local tid ops=""
    for tid in "$@"; do
        ops+="$(waiting_ops "$tid")"$'\n'
    done
    [[ -n "${ops//$'\n'/}" ]] || return 0
    notmuch tag --batch <<<"$ops"
}

# The database's uuid and revision, as "uuid rev".
db_revision() {
    notmuch count --lastmod '*' | awk -F'\t' '{print $2, $3}'
}

# Seeds the seen set with every message of the last SEEN_DAYS and records the
# revision, so the first run fires nothing.
seed() {
    local now
    now="$(date +%s)"
    notmuch search --output=messages "date:${SEEN_DAYS}days.." | sed "s/^id://; s/\$/\t${now}/" >"$STATE_DIR/seen"
    printf '%s\n' "$1" >"$STATE_DIR/revision"
}

run_hook() {
    local revision uuid rev last_uuid last now id
    local -a fresh=() touched=()
    mkdir -p "$STATE_DIR"
    exec 8>"$STATE_DIR/lock"
    flock -w 120 8 || fail "another post-new run held $STATE_DIR/lock past 120s"
    load_self

    revision="$(db_revision)" || fail "cannot read the notmuch revision"
    read -r uuid rev <<<"$revision"
    if [[ -f "$STATE_DIR/revision" ]]; then
        read -r last_uuid last <"$STATE_DIR/revision" || true
    fi
    if [[ "$last_uuid" != "$uuid" || ! "$last" =~ ^[0-9]+$ || ! -f "$STATE_DIR/seen" ]]; then
        seed "$revision"
        discharge_handoffs
        check_watches
        return 0
    fi

    if ((rev > last)); then
        now="$(date +%s)"
        # Messages added or modified since the last run, minus those already seen.
        mapfile -t fresh < <(notmuch search --uuid="$uuid" --output=messages \
            "lastmod:$((last + 1))..${rev} and date:${DAYS}days.." | sed 's/^id://' |
            awk -F'\t' 'NR == FNR {seen[$1] = 1; next} !($0 in seen)' "$STATE_DIR/seen" -)
        for id in "${fresh[@]}"; do
            event_for "$id" || fail "cannot build the event for message $id"
            printf '%s\t%s\n' "$id" "$now" >>"$STATE_DIR/seen"
        done
        if ((${#fresh[@]} > 0)); then
            rearm "${fresh[@]}" || fail "cannot re-arm gordon/cleared"
        fi
        mapfile -t touched < <(notmuch search --uuid="$uuid" --output=threads \
            "lastmod:$((last + 1))..${rev} and date:${DAYS}days.." | sed 's/^thread://')
        if ((${#touched[@]} > 0)); then
            recompute "${touched[@]}" || fail "cannot update the waiting tags"
        fi
        # Forget ids older than SEEN_DAYS.
        awk -F'\t' -v cut="$((now - SEEN_DAYS * 86400))" '$2 >= cut' "$STATE_DIR/seen" >"$STATE_DIR/seen.tmp"
        mv -f "$STATE_DIR/seen.tmp" "$STATE_DIR/seen"
    fi
    printf '%s %s\n' "$uuid" "$rev" >"$STATE_DIR/revision"
    discharge_handoffs
    check_watches
}

# Close a mail handoff (`close-when: mail-sent <thread>`) once Piotr's sent
# reply lands, so it leaves his margin on the sync that carries the evidence
# rather than whenever Gordon next looks. Bounded and failure-tolerant: a
# broken check never fails mail indexing.
discharge_handoffs() {
    [[ -x "$HANDOFF_CHECK" ]] || return 0
    timeout "${MAIL_EVENTS_HANDOFF_TIMEOUT:-20}" "$HANDOFF_CHECK" --close --kind mail-sent >/dev/null 2>&1 || true
}

# Mail thread-watch subscriptions learn about new mail from this hook.
check_watches() {
    local out
    [[ -x "$THREAD_WATCH" ]] || return 0
    if ! out="$("$THREAD_WATCH" check-source mail 2>&1)"; then
        fail "thread-watch check-source mail: ${out:0:300}"
    fi
}

backfill() {
    local days="$1"
    local -a threads=()
    [[ "$days" =~ ^[0-9]+$ ]] || {
        echo "--backfill takes a number of days" >&2
        exit 1
    }
    load_self
    mapfile -t threads < <(notmuch search --output=threads "date:${days}days.." | sed 's/^thread://')
    ((${#threads[@]} == 0)) || recompute "${threads[@]}"
    printf 'recomputed %s threads; waiting/me:\n' "${#threads[@]}"
    notmuch search 'tag:waiting/me'
}

case "${1:-}" in
"") run_hook ;;
--backfill) backfill "${2:-}" ;;
-h | --help) sed -n '2,/^set -eo/p' "$0" | sed '$d; s/^# \{0,1\}//' ;;
*)
    echo "usage: ${0##*/} [--backfill <days>]" >&2
    exit 1
    ;;
esac
