#!/usr/bin/env bash
# PROJECT: reminders
#
# A reminder is a pointer plus a trigger. The record holds a label, a time or a
# repeat, an action and an optional typed subject (task:<uuid>, url:<url>,
# text:<free text>). It never copies the subject's content: a task is read live
# by uuid when the reminder fires.
#
# The JSONL store is the only truth: one record per line, append-only, the last
# record per id wins, `gc` compacts. `sync` derives the clocks from it and is
# never hand-written: one-shots become `at -q r -t` jobs, repeats become lines
# in a managed crontab block wrapped by __cron_run.sh (and __cron_every.sh for
# intervals, so a box that is off overnight still catches up). Both clocks call
# back `fire <id>` with nothing but the id, so labels never reach a shell.
#
# Every fire appends one line to the fire log. Snooze is an edit of `when` plus
# `sync`; a dismissed or dying dialog snoozes by default, so no path drops a
# reminder.
# The fire log rolls at 1 MiB, keeping three older generations (.1 plain,
# .2.gz and .3.gz). Reports read that retained history oldest first.
#
# An exec reminder is a packet: a check, the actions it runs, and a deadline.
# The check's exit code is the verdict: 0 not yet, 2 success, 3 failure, 4
# withdrawn, else an execution error. Success or failure completes the packet
# once: the verdict is latched, its ordered actions run, and a trace and report
# task are written before it retires. Failed actions retry without rerunning
# the check or completed actions. Withdrawn retires it quietly, with a
# fire.log line and no task: Piotr ended what it watched (closed the linked
# task), so a report would tell him nothing. Exit 4 withdraws only when the
# last output line starts with "withdrawn:"; gh (expired login) and wget
# (network failure) also exit 4, and a check passing that through is an error. An execution error opens one task
# for an AI and keeps the schedule. The deadline is the one reminder on a clock: when it passes with
# neither verdict, Piotr gets the form (extend, send to AI, delete) and Gordon a
# line; the packet keeps running.
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$(readlink -f "${BASH_SOURCE[0]}")"
DEFAULT_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/reminders"
STATE_DIR="${REMINDER_STATE_DIR:-$DEFAULT_STATE_DIR}"
STORE="${REMINDER_STORE:-$STATE_DIR/reminders.jsonl}"
FIRE_LOG="${REMINDER_LOG:-$STATE_DIR/fire.log}"
LOCK="${STORE}.lock"
GUI="${REMINDER_GUI:-$SCRIPT_DIR/__reminder_gui.py}"
URL_OPENER="${REMINDER_URL_OPENER:-$SCRIPT_DIR/__taskopen_url_open.sh}"
TASK_OPENER="${REMINDER_TASK_OPENER:-$SCRIPT_DIR/__task_open.sh}"
MAILER="${REMINDER_MAILER:-$SCRIPT_DIR/__mail_me.sh}"
# Send to AI: Gordon over the agents bus when his pane is up, else a new
# Claude window in the attached tmux session.
SND="${REMINDER_SND:-$HOME/.claude/scripts/snd}"
TMUX_BIN="${REMINDER_TMUX:-tmux}"
CLAUDE_LAUNCHER="${REMINDER_CLAUDE:-$HOME/.claude/scripts/__claude_with_monitor.sh}"
AI_CWD="${REMINDER_AI_CWD:-$HOME/dev/dotfiles}"
CRON_RUN="${REMINDER_CRON_RUN:-$SCRIPT_DIR/__cron_run.sh}"
CRON_EVERY="${REMINDER_CRON_EVERY:-$SCRIPT_DIR/__cron_every.sh}"
STAMP_DIR="${CRON_EVERY_STAMP_DIR:-$HOME/.local/state/cron-every}"
AT_QUEUE="r"
CRON_BEGIN="# BEGIN remind (managed by __reminder.sh sync, edits here are overwritten)"
CRON_END="# END remind"
DEFAULT_SNOOZE="${REMINDER_DEFAULT_SNOOZE:-15 minutes}"
LATE_AFTER=300
NOTIFY_LOG="${NOTIFY_LOG:-${XDG_STATE_HOME:-$HOME/.local/state}/notifications.log}"
# Notification triggers (docs/notify-triggers.md): `watch` tails NOTIFY_LOG from
# its own cursor and fires every active on_notify record a popup matches. A
# delayed fire goes to at queue n, which sync never rebuilds, with the popup in
# a match file named by a token; the job body carries the id and the token only.
NOTIFY_AT_QUEUE="n"
NOTIFY_CURSOR="$STATE_DIR/notify.cursor"
NOTIFY_SEEN="$STATE_DIR/notify.seen"
NOTIFY_ALIVE="$STATE_DIR/notify.alive"
NOTIFY_PATTERNS="$STATE_DIR/notify-patterns.txt"
MATCH_DIR="$STATE_DIR/matches"
NOTIFY_WINDOW="${REMINDER_NOTIFY_WINDOW:-900}"
NOTIFY_TIMEOUT="${REMINDER_NOTIFY_TIMEOUT:-120}"
NOTIFY_POLL="${REMINDER_NOTIFY_POLL:-5}"

usage() {
	cat <<'USAGE'
Usage: remind [<verb> [args]]   (no verb: the agenda, the whole list in $EDITOR)

  add <label> <when> [options]      one-shot reminder
  add <label> --repeat <spec> [options]   an exec repeat needs --deadline
  add <label> --on-notify <regex> --action exec --command <cmd> [--delay 10m]
                                    fires on every desktop popup the regex matches
  list [--json] [--all]             active records (or every record with --all)
  edit <id> [options]               change fields, then sync
  edit <id>                         open the record in $EDITOR, apply what changed
  agenda                            the whole list as an org file in $EDITOR; save applies
  agenda render | apply [file]      the two halves, for scripts and agents

Agenda format (org): one ** heading per reminder, properties indented below.
  ** <2026-09-27 Sun 22:00> title          one-shot; <0 9 * * 1> or <every 7d> repeats
     :action: open|exec                    omitted means show
     :runs: command                        what an exec runs (exit 2 = hit, retires it)
     :task: <uuid> | :url: <link> | :notes: text   what it points at, one per reminder
     :id: 9ed4fac6                         omit it on a heading you add
  A heading you delete deletes the reminder. # lines and * section lines are ignored.
  done <id>                         mark done (a repeat keeps its schedule)
  delete <id>
  sync                              rebuild the at queue and the crontab block
  gc                                compact the store to active records, drop stale fire locks
  compact                           one line per reminder, done and deleted kept (runs at boot)
  rotate-log                        rotate fire.log if it has reached 1 MiB; clocks unchanged
  fire <id> [token]                 what the clocks call; runs the action
  deadline <id>                     what the deadline clock calls; shows the form
  match                             one pass over new notification log lines
  watch                             match forever (reminder-watch.service)
  watch <thread-url> [--task <uuid>] [--label t] [--every 30m] [--once]
                                    subscribe to a thread (__thread_watch.sh subscribe);
                                    --once ends it on the first reply

Options for add and edit:
  --when <spec>       10m 2h 1d 1w, tomorrow, eod, eow, or anything date -d
                      accepts: 'Tuesday 16:20', '2026-09-10 09:30', 'next monday 9:00'
  --repeat <spec>     5-field cron ('0 9 * * 1') or 'every 7d' (m h d w units)
  --on-notify <re>    regex over a whole notification log record
                      "date time<TAB>app<TAB>summary<TAB>body"; the reminder stays
                      active and runs its exec command once per matching popup,
                      popup on stdin and in $REMINDER_MATCH; exit 0 is success,
                      anything else reaches Gordon (--to gordon) or your mail
  --delay <spec>      with --on-notify: fire that long after the popup (10m 2h), via at
  --deadline <spec>   when the check must have settled, same specs as --when; past
                      it with no verdict you get the form (extend, send to AI, delete)
                      and Gordon a line; the packet keeps running
  --subject <s>       task:<uuid>, url:<url>, or free text (stored as text:)
  --action <a>        show (default), open, exec
  --notify <n>        dialog (default), mail, or silent: how a show reaches you; mail
                      also copies an exec verdict or error
  --on-hit <shell>    add an action after success (exit 2); repeat for more actions
  --on-fail <shell>   add an action after failure (exit 3); repeat for more actions
                      actions run in order with check output on stdin; failures do
                      not stop later actions. Only failed actions retry, without
                      rerunning the check. On edit, flags replace that action array
  --on-miss <shell>   runs after not yet (exit 0), same; a failing hook is an
                      execution error and the schedule stays
  --command <cmd>     literal command for the exec action; its exit code is the
                      verdict: 0 not yet, 2 success, 3 failure (both write the trace
                      and a report task, then retire it), 4 withdrawn (retire
                      quietly, no task: what it watched was ended by hand; the
                      last output line must start with "withdrawn:"), else
                      an execution error (one task for Gordon, the schedule
                      stays); it sees its packet id in $REMINDER_ID
  --origin <o>        who created it (cli, claude, dialog, migrate)
  --to <r>            piotr (default, a dialog) or gordon (a line in the notification
                      log that Gordon's session reads; falls back to the dialog)

Dialog bindings used by the Argos applet:
  add-dialog, edit-dialog <id>, delete-dialog <id>, open <id>
USAGE
}

die() {
	printf '%s\n' "$*" >&2
	exit 1
}

now_iso() {
	date +%Y-%m-%dT%H:%M:%S%:z
}

# ---------------------------------------------------------------- store ----

prepare_store() {
	mkdir -p "$(dirname "$STORE")"
	[ -f "$STORE" ] || : >"$STORE"
	touch "$LOCK"
}

lock_store() {
	exec 9>"$LOCK"
	flock 9
}

unlock_store() {
	flock -u 9
}

append_record() {
	prepare_store
	lock_store
	printf '%s\n' "$1" >>"$STORE"
	unlock_store
}

# The last record per id wins. jq keeps object insertion order, so records
# come out in first-seen order.
current_records() {
	prepare_store
	jq -c -s 'reduce .[] as $r ({}; .[$r.id] = $r) | .[]' "$STORE"
}

active_records() {
	current_records | jq -c -s 'map(select(.status == "active")) | sort_by(.when // "9999") | .[]'
}

get_record() {
	local id="$1" record
	record="$(current_records | jq -c --arg id "$id" 'select(.id == $id)' | tail -n1)"
	[ -n "$record" ] || return 1
	printf '%s' "$record"
}

# Apply a jq filter to the current record and append the result. Empty and
# null fields are dropped so `del(.when)` and `.when = ""` both clear a field.
# The read, the filter and the append share one lock: two writers that each
# read the same record and appended a full replacement lost one edit.
update_record() {
	local id="$1" filter="$2" record updated
	shift 2
	prepare_store
	lock_store
	record="$(get_record "$id")" || die "No reminder with id $id."
	updated="$(jq -c "$@" "$filter | with_entries(select(.value != null and .value != \"\"))" <<<"$record")"
	printf '%s\n' "$updated" >>"$STORE"
	unlock_store
}

new_id() {
	od -An -N4 -tx1 /dev/urandom | tr -d ' \n'
}

valid_id() {
	[[ "$1" =~ ^[0-9a-f]{8}$ ]]
}

# ---------------------------------------------------------------- time -----

# Any spec becomes an exact local timestamp at minute precision, which is
# what `at -t` takes. Shorthands first, then GNU date's own grammar.
parse_when() {
	local spec="$1" expr
	case "$spec" in
	tomorrow) expr='tomorrow 9:00' ;;
	eod) expr='today 20:00' ;;
	eow) expr='next friday 12:00' ;;
	*)
		if [[ "$spec" =~ ^([0-9]+)([mhdw])$ ]]; then
			case "${BASH_REMATCH[2]}" in
			m) expr="${BASH_REMATCH[1]} minutes" ;;
			h) expr="${BASH_REMATCH[1]} hours" ;;
			d) expr="${BASH_REMATCH[1]} days" ;;
			w) expr="${BASH_REMATCH[1]} weeks" ;;
			esac
		else
			expr="$spec"
		fi
		;;
	esac
	date -d "$expr" +%Y-%m-%dT%H:%M:00%:z 2>/dev/null || return 1
}

# Accepts a 5-field cron line or `every <N><unit>`; returns the normalized form.
parse_repeat() {
	local spec="$1"
	if [[ "$spec" =~ ^every[[:space:]]+([0-9]+)([mhdw])$ ]]; then
		printf 'every %s%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
		return 0
	fi
	local -a fields
	read -ra fields <<<"$spec"
	[ "${#fields[@]}" -eq 5 ] || return 1
	local f
	for f in "${fields[@]}"; do
		[[ "$f" =~ ^[0-9A-Za-z*,/-]+$ ]] || return 1
	done
	printf '%s' "${fields[*]}"
}

every_seconds() {
	[[ "$1" =~ ^every\ ([0-9]+)([mhdw])$ ]] || return 1
	local n="${BASH_REMATCH[1]}"
	case "${BASH_REMATCH[2]}" in
	m) printf '%s' $((n * 60)) ;;
	h) printf '%s' $((n * 3600)) ;;
	d) printf '%s' $((n * 86400)) ;;
	w) printf '%s' $((n * 604800)) ;;
	esac
}

at_time() {
	date -d "$1" +%Y%m%d%H%M
}

epoch_of() {
	date -d "$1" +%s
}

# A date for a person. The year appears when the date is over half a year away,
# as in ls, so a 2036 deadline cannot read as last week.
human_when() {
	local away=$(($(date -d "$1" +%s) - $(date +%s)))
	if [ "${away#-}" -gt 15552000 ]; then
		date -d "$1" '+%a %d %b %Y %H:%M'
	else
		date -d "$1" '+%a %d %b %H:%M'
	fi
}

human_duration() {
	local s="$1"
	if [ "$s" -ge 86400 ]; then
		printf '%dd %dh' $((s / 86400)) $((s % 86400 / 3600))
	elif [ "$s" -ge 3600 ]; then
		printf '%dh %dm' $((s / 3600)) $((s % 3600 / 60))
	else
		printf '%dm' $((s / 60))
	fi
}

# This box is off roughly 23:30 to 09:00. A one-shot in that window fires at
# boot (atd runs every overdue spool job on its first pass); a cron line pinned
# there never fires at all, so the warning is the whole safety net.
warn_off_window() {
	local kind="$1" hour="$2" minute="$3"
	if [ "$hour" -lt 9 ] || { [ "$hour" -eq 23 ] && [ "$minute" -ge 30 ]; }; then
		if [ "$kind" = when ]; then
			printf 'Warning: %02d:%02d is in the off window (23:30-09:00); it will fire at the next boot.\n' "$hour" "$minute" >&2
		else
			printf 'Warning: cron hour %02d is in the off window (23:30-09:00); a pinned repeat never fires there. Use "every <N>d" for catch-up.\n' "$hour" >&2
		fi
	fi
}

check_off_window() {
	local when="$1" repeat="$2" hour minute
	if [ -n "$when" ]; then
		hour="$((10#$(date -d "$when" +%H)))"
		minute="$((10#$(date -d "$when" +%M)))"
		warn_off_window when "$hour" "$minute"
	fi
	if [[ "$repeat" =~ ^([0-9]+)[[:space:]]+([0-9]+)[[:space:]] ]]; then
		warn_off_window repeat "$((10#${BASH_REMATCH[2]}))" "$((10#${BASH_REMATCH[1]}))"
	fi
}

# ------------------------------------------------------------- subjects ----

# Typed subjects keep their prefix; anything else is the reminder's own text.
normalize_subject() {
	local subject="$1" uuid
	case "$subject" in
	'') printf '' ;;
	task:*)
		uuid="${subject#task:}"
		if command -v task >/dev/null 2>&1; then
			uuid="$(task rc.verbose=nothing rc.hooks=off _get "${uuid}.uuid" 2>/dev/null || true)"
			[ -n "$uuid" ] || die "No task matches ${subject#task:}."
		fi
		printf 'task:%s' "$uuid"
		;;
	url:*) printf '%s' "$subject" ;;
	text:*) printf '%s' "$subject" ;;
	*) printf 'text:%s' "$subject" ;;
	esac
}

subject_type() {
	case "$1" in
	task:*) printf 'task' ;;
	url:*) printf 'url' ;;
	text:*) printf 'text' ;;
	*) printf '' ;;
	esac
}

# Mirrors .taskopenrc's annotation grammar: a "link: <url>" line wins over a
# bare url elsewhere in the text.
first_url() {
	local text="$1" url
	url="$(grep -om1 '^[[:space:]]*link:[[:space:]]\+https\?://[^[:space:]]\+' <<<"$text" \
		| head -n1 | sed 's/^[[:space:]]*link:[[:space:]]*//')" || true
	if [ -n "$url" ]; then
		printf '%s' "$url"
		return 0
	fi
	url="$(grep -om1 'https\?://[^[:space:]]\+' <<<"$text" | head -n1)" || true
	[ -n "$url" ] || return 1
	printf '%s' "$url"
}

subject_url() {
	case "$1" in
	url:*) printf '%s' "${1#url:}" ;;
	text:*) first_url "${1#text:}" ;;
	*) return 1 ;;
	esac
}

task_field() {
	task rc.verbose=nothing rc.hooks=off _get "$1.$2" 2>/dev/null || true
}

# Live view of a subject for display. A task is read now, by uuid.
subject_body() {
	case "$1" in
	task:*) task_field "${1#task:}" description ;;
	url:*) printf '%s' "${1#url:}" ;;
	text:*) printf '%s' "${1#text:}" ;;
	esac
}

# Title for a record: the label, else the live task description, else the subject.
record_title() {
	local record="$1" label subject body
	label="$(jq -r '.label // ""' <<<"$record")"
	if [ -n "$label" ]; then
		printf '%s' "$label"
		return 0
	fi
	subject="$(jq -r '.subject // ""' <<<"$record")"
	body="$(subject_body "$subject")"
	printf '%s' "${body:-$subject}"
}

open_url() {
	"$URL_OPENER" "$1" >/dev/null 2>&1
}


# ---------------------------------------------------------------- clocks ---

# Every queue-r job, one line each: job_id <TAB> epoch <TAB> verb:id. The
# body ends in `fire <id>` (the reminder's time) or `deadline <id>` (its
# deadline); the environment dump above it is never parsed.
at_jobs() {
	local job_id day month date clock year _queue _owner key
	while read -r job_id day month date clock year _queue _owner; do
		[[ "$job_id" =~ ^[0-9]+$ ]] || continue
		key="$(at -c "$job_id" 2>/dev/null | grep -oE '(fire|deadline) [0-9a-f]{8}[[:space:]]*$' | tail -n1 | awk '{print $1 ":" $2}')" || true
		printf '%s\t%s\t%s\n' "$job_id" "$(epoch_of "$day $month $date $clock $year")" "${key:-}"
	done < <(atq -q "$AT_QUEUE" 2>/dev/null || true)
}

at_schedule() {
	local key="$1" when="$2" output status=0
	output="$(printf '%q %s %s\n' "$SELF" "${key%%:*}" "${key#*:}" | at -q "$AT_QUEUE" -t "$(at_time "$when")" 2>&1)" || status=$?
	if [ "$status" -ne 0 ]; then
		printf 'at rejected %s for %s:\n%s\n' "$when" "$key" "$output" >&2
		return "$status"
	fi
}

# When the deadline clock should ring: the deadline, or the retry a dismissed
# form left; nothing once a verdict is latched or Piotr handled the deadline. A time
# already past is kept as is: at runs it at once.
deadline_due() {
	jq -r 'if (.deadline // "") == "" or .deadline_seen == .deadline or .verdict != null then ""
		else (.deadline_retry // .deadline) end' <<<"$1"
}

sync_at() {
	local -A desired=() present=() due_at=()
	local id when job_id epoch key record created=0 removed=0 failed=0

	while IFS= read -r record; do
		id="$(jq -r '.id' <<<"$record")"
		when="$(jq -r '.when // ""' <<<"$record")"
		[ -n "$when" ] && desired["fire:$id"]="$(epoch_of "$when")" due_at["fire:$id"]="$when"
		when="$(deadline_due "$record")"
		[ -n "$when" ] && desired["deadline:$id"]="$(epoch_of "$when")" due_at["deadline:$id"]="$when"
	done < <(active_records)

	while IFS=$'\t' read -r job_id epoch key; do
		if [ -n "$key" ] && [ "${desired[$key]:-}" = "$epoch" ] && [ -z "${present[$key]:-}" ]; then
			present["$key"]=1
		else
			atrm "$job_id" && removed=$((removed + 1))
		fi
	done < <(at_jobs)

	for key in "${!desired[@]}"; do
		[ -n "${present[$key]:-}" ] && continue
		if at_schedule "$key" "${due_at[$key]}"; then
			created=$((created + 1))
		else
			failed=$((failed + 1))
		fi
	done
	[ "$((created + removed))" -eq 0 ] || printf 'at: %s created, %s removed\n' "$created" "$removed"
	[ "$failed" -eq 0 ]
}

cron_line() {
	local id="$1" repeat="$2" seconds
	if seconds="$(every_seconds "$repeat")"; then
		printf '*/15 * * * * %s remind-%s %s -- %s remind-%s -- %s fire %s\n' \
			"$CRON_EVERY" "$id" "$seconds" "$CRON_RUN" "$id" "$SELF" "$id"
	else
		printf '%s %s remind-%s -- %s fire %s\n' "$repeat" "$CRON_RUN" "$id" "$SELF" "$id"
	fi
}

cron_block() {
	local record id repeat
	printf '%s\n' "$CRON_BEGIN"
	printf '@reboot sleep 90 && %s sync; %s compact\n' "$SELF" "$SELF"
	while IFS= read -r record; do
		id="$(jq -r '.id' <<<"$record")"
		repeat="$(jq -r '.repeat // ""' <<<"$record")"
		[ -n "$repeat" ] && cron_line "$id" "$repeat"
	done < <(active_records)
	printf '%s\n' "$CRON_END"
}

sync_cron() {
	local current stripped block updated
	current="$(crontab -l 2>/dev/null || true)"
	stripped="$(awk -v b="$CRON_BEGIN" -v e="$CRON_END" '$0 == b {skip=1} !skip {print} $0 == e {skip=0}' <<<"$current")"
	block="$(cron_block)"
	updated="$(printf '%s\n\n%s\n' "$stripped" "$block" | sed '/./,$!d')"
	[ "$updated" != "$current" ] || return 0
	mkdir -p "$STATE_DIR"
	printf '%s\n' "$current" >"$STATE_DIR/crontab.previous"
	printf '%s\n' "$updated" | crontab -
	printf 'crontab: managed block rewritten\n'
}

# `every <N><unit>` repeats leave a stamp under cron-every/remind-<id> that
# __cron_every.sh advances; nothing else ever removed one, so a retired
# reminder kept its stamp until someone deleted it by hand.
sync_stamps() {
	local stamp id
	[ -d "$STAMP_DIR" ] || return 0
	for stamp in "$STAMP_DIR"/remind-*; do
		[ -f "$stamp" ] || continue
		id="${stamp##*/remind-}"
		active_records | jq -e --arg id "$id" 'select(.id == $id and (.repeat // "" | startswith("every ")))' >/dev/null && continue
		rm -f "$stamp"
		printf 'stamp: dropped remind-%s\n' "$id"
	done
}

# The at queue, the crontab block and the cron-every stamps are one per user,
# not one per store. A sync from any other store reaps every job and repeat it
# does not know: a scratch-store smoke test on 2026-09-08 took 7 real jobs.
# Only the default store drives them, unless REMINDER_OWN_CLOCKS says the
# clocks are this store's own (the tests, which stub at and crontab).
own_clocks() {
	[ -n "${REMINDER_OWN_CLOCKS:-}" ] && return 0
	[ "$(realpath -m "$STORE")" = "$(realpath -m "$DEFAULT_STATE_DIR/reminders.jsonl")" ]
}

# Sync reads the at queue, then schedules what is missing. Two unlocked passes
# both saw a job missing and both scheduled it; every duplicate fired, and each
# fire synced again, so on 2026-09-09 one reminder fired 2, 4, then 7 times.
cmd_sync() {
	local rc=0
	own_clocks || die "sync: $STORE is not the default store, so it may not touch the shared at queue, crontab or cron-every stamps."
	mkdir -p "$STATE_DIR"
	exec 7>"$STATE_DIR/sync.lock"
	flock 7
	sync_at || rc=$?
	sync_cron || rc=$?
	sync_stamps || rc=$?
	sync_patterns || rc=$?
	flock -u 7
	exec 7>&-
	return "$rc"
}

# The notify-watch mod drops a popup an active on-notify reminder claims, so
# it never reaches Gordon twice. It reads this file, one regex per line in
# ignore.txt's format, derived here like the clocks. Written whole and moved
# into place, so a reader never sees half a list.
sync_patterns() {
	local block current=""
	block="$(active_records | jq -r 'select(.on_notify) | .on_notify')"
	[ -f "$NOTIFY_PATTERNS" ] && current="$(cat "$NOTIFY_PATTERNS")"
	[ "$block" != "$current" ] || return 0
	mkdir -p "$STATE_DIR"
	printf '%s\n' "$block" | sed '/^$/d' >"$NOTIFY_PATTERNS.tmp"
	mv "$NOTIFY_PATTERNS.tmp" "$NOTIFY_PATTERNS"
	printf 'patterns: %s on-notify rule(s) written\n' "$(grep -c '' "$NOTIFY_PATTERNS" || true)"
}

# ------------------------------------------------------------------ log ----

# Caller holds the fire-log lock. Leave the newest archive plain for any
# writer already in flight when this version of the helper was installed.
rotate_fire_log_locked() {
	[ -f "$FIRE_LOG" ] || return 0
	[ "$(stat -c %s "$FIRE_LOG")" -ge 1048576 ] || return 0
	if [ -f "$FIRE_LOG.1" ]; then
		# Finish compression before changing any existing generation.
		gzip -c -- "$FIRE_LOG.1" >"$FIRE_LOG.2.gz.tmp"
		[ ! -f "$FIRE_LOG.2.gz" ] || mv -f -- "$FIRE_LOG.2.gz" "$FIRE_LOG.3.gz"
		mv -f -- "$FIRE_LOG.2.gz.tmp" "$FIRE_LOG.2.gz"
		rm -- "$FIRE_LOG.1"
	fi
	mv -- "$FIRE_LOG" "$FIRE_LOG.1"
	touch -- "$FIRE_LOG"
	chmod --reference="$FIRE_LOG.1" -- "$FIRE_LOG"
}

# Explicit maintenance uses the same lock and threshold as each append.
cmd_rotate_log() {
	mkdir -p "$(dirname "$FIRE_LOG")"
	(
		flock 5
		rotate_fire_log_locked
	) 5>>"$FIRE_LOG.lock"
}

# Keep readers on one consistent set of generations while rotation waits.
fire_history() {
	[ -d "$(dirname "$FIRE_LOG")" ] || return 0
	(
		flock -s 5
		local generation
		for generation in 3 2; do
			[ ! -f "$FIRE_LOG.$generation.gz" ] || gzip -cd -- "$FIRE_LOG.$generation.gz"
		done
		[ ! -f "$FIRE_LOG.1" ] || cat -- "$FIRE_LOG.1"
		[ ! -f "$FIRE_LOG" ] || cat -- "$FIRE_LOG"
	) 5>>"$FIRE_LOG.lock"
}

# Serialize the size check, rotation and append across concurrent reminders.
log_fire() {
	local id="$1" event="$2" detail="$3" label="$4"
	mkdir -p "$(dirname "$FIRE_LOG")"
	(
		flock 5
		rotate_fire_log_locked
		printf '%s\t%s\t%s\t%s\t%s\n' "$(now_iso)" "$id" "$event" "$detail" "$(printf '%s' "$label" | tr '\t\n' '  ')" >>"$FIRE_LOG"
	) 5>>"$FIRE_LOG.lock"
}

# ---------------------------------------------------------------- verbs ----

parse_options() {
	# Fills opt_* variables and positional[] from "$@".
	opt_when="" opt_repeat="" opt_subject="" opt_action="" opt_command="" opt_origin="" opt_label="" opt_notify="" opt_on_hit="" opt_on_miss="" opt_to="" opt_on_notify="" opt_delay="" opt_deadline="" opt_on_fail=""
	positional=()
	opt_on_hit='[]' opt_on_fail='[]' opt_on_hit_set=0 opt_on_fail_set=0
	while [ $# -gt 0 ]; do
		case "$1" in
		--when) opt_when="${2:-}"; shift 2 ;;
		--deadline) opt_deadline="${2:-}"; shift 2 ;;
		--on-fail) opt_on_fail_set=1; opt_on_fail="$(jq -c --arg action "${2:-}" '. + (if $action == "" then [] else [$action] end)' <<<"$opt_on_fail")"; shift 2 ;;
		--repeat) opt_repeat="${2:-}"; shift 2 ;;
		--on-notify) opt_on_notify="${2:-}"; shift 2 ;;
		--delay) opt_delay="${2:-}"; shift 2 ;;
		--subject) opt_subject="${2:-}"; shift 2 ;;
		--action) opt_action="${2:-}"; shift 2 ;;
		--command) opt_command="${2:-}"; shift 2 ;;
		--notify) opt_notify="${2:-}"; shift 2 ;;
		--on-hit) opt_on_hit_set=1; opt_on_hit="$(jq -c --arg action "${2:-}" '. + (if $action == "" then [] else [$action] end)' <<<"$opt_on_hit")"; shift 2 ;;
		--on-miss) opt_on_miss="${2:-}"; shift 2 ;;
		--origin) opt_origin="${2:-}"; shift 2 ;;
		--to) opt_to="${2:-}"; shift 2 ;;
		--label) opt_label="${2:-}"; shift 2 ;;
		--) shift; positional+=("$@"); break ;;
		-*) die "Unknown option $1" ;;
		*) positional+=("$1"); shift ;;
		esac
	done
}

validate_notify() {
	case "$1" in
	'' | dialog | mail | silent) ;;
	*) die "Unknown notify $1 (dialog, mail, silent)." ;;
	esac
}

validate_to() {
	case "$1" in
	'' | piotr | gordon) ;;
	*) die "Unknown recipient $1 (piotr, gordon)." ;;
	esac
}

validate_action() {
	case "$1" in
	show | open) ;;
	exec) [ -n "$2" ] || die "The exec action needs a command." ;;
	*) die "Unknown action $1 (show, open, exec)." ;;
	esac
}

# A pattern is compiled by jq's test, the dialect the notify-watch mod's
# RegExp shares for these records (\t for the field separator, no lookbehind).
# Compile it now so a typo fails the add, not every match pass.
validate_pattern() {
	[ -n "$1" ] || die "--on-notify needs a regex."
	jq -ne --arg re "$1" '"" | test($re) | true' >/dev/null 2>&1 || die "Cannot compile pattern: $1"
}

# A delay is `<N><unit>` like the shorthands parse_when takes; returned as is.
parse_delay() {
	[[ "$1" =~ ^[0-9]+[mhdw]$ ]] || return 1
	printf '%s' "$1"
}

delay_seconds() {
	every_seconds "every $1"
}

# The three trigger kinds exclude each other: a popup-triggered reminder has
# no clock, so sync never schedules it and a dialog never snoozes it.
validate_trigger() {
	local when="$1" repeat="$2" on_notify="$3" delay="$4" action="$5"
	if [ -n "$on_notify" ]; then
		if [ -n "$when" ] || [ -n "$repeat" ]; then die "--on-notify takes no time or repeat."; fi
		[ "$action" = exec ] || die "--on-notify needs --action exec."
		validate_pattern "$on_notify"
	else
		[ -z "$delay" ] || die "--delay needs --on-notify."
	fi
	if [ -n "$delay" ]; then
		parse_delay "$delay" >/dev/null || die "Cannot parse delay: $delay (10m 2h 1d 1w)"
	fi
}

cmd_add() {
	local label when repeat subject action id record deadline=""
	parse_options "$@"
	label="${opt_label:-${positional[0]:-}}"
	when="${opt_when:-${positional[1]:-}}"
	[ -n "$label" ] || [ -n "$opt_subject" ] || die "A reminder needs a label or a subject."
	[ -n "$when" ] || [ -n "$opt_repeat" ] || [ -n "$opt_on_notify" ] || die "A reminder needs a time (<when>), --repeat, or --on-notify."
	if [ -n "$when" ]; then
		when="$(parse_when "$when")" || die "Cannot parse time: $when"
	fi
	repeat=""
	if [ -n "$opt_repeat" ]; then
		repeat="$(parse_repeat "$opt_repeat")" || die "Cannot parse repeat: $opt_repeat"
	fi
	if [ -n "$opt_deadline" ]; then
		deadline="$(parse_when "$opt_deadline")" || die "Cannot parse deadline: $opt_deadline"
	fi
	subject="$(normalize_subject "$opt_subject")"
	action="${opt_action:-show}"
	validate_action "$action" "$opt_command"
	validate_trigger "$when" "$repeat" "$opt_on_notify" "$opt_delay" "$action"
	# A repeating check with no deadline is a cron job: nothing ever says it
	# stopped making sense. Popup rules are event handlers and stay open.
	if [ "$action" = exec ] && [ -n "$repeat" ] && [ -z "$deadline" ]; then
		die "An exec repeat needs --deadline: when must it have succeeded or failed?"
	fi
	validate_notify "$opt_notify"
	validate_to "$opt_to"
	id="$(new_id)"
	record="$(jq -nc --arg id "$id" --arg label "$label" --arg when "$when" --arg repeat "$repeat" \
		--arg action "$action" --arg subject "$subject" --arg command "$opt_command" \
		--arg notify "$opt_notify" --argjson on_hit "$opt_on_hit" --arg on_miss "$opt_on_miss" \
		--arg created "$(now_iso)" --arg origin "${opt_origin:-cli}" --arg to "$opt_to" \
		--arg on_notify "$opt_on_notify" --arg delay "$opt_delay" \
		--arg deadline "$deadline" --argjson on_fail "$opt_on_fail" \
		'{id:$id, label:$label, when:$when, repeat:$repeat, on_notify:$on_notify, delay:$delay,
		  deadline:$deadline, action:$action, subject:$subject,
		  command:$command, notify:$notify, on_hit:$on_hit, on_fail:$on_fail, on_miss:$on_miss,
		  created:$created, origin:$origin, to:$to, status:"active"}
		 | with_entries(select(.value != "" and .value != []))')"
	append_record "$record"
	check_off_window "$when" "$repeat"
	cmd_sync >/dev/null
	local by="${deadline:+, deadline $(human_when "$deadline")}"
	if [ -n "$when" ]; then
		printf 'Added %s: %s at %s%s\n' "$id" "$(record_title "$record")" "$(human_when "$when")" "$by"
	elif [ -n "$opt_on_notify" ]; then
		printf 'Added %s: %s on popup /%s/%s%s\n' "$id" "$(record_title "$record")" "$opt_on_notify" "${opt_delay:+, after $opt_delay}" "$by"
	else
		printf 'Added %s: %s, repeat %s%s\n' "$id" "$(record_title "$record")" "$repeat" "$by"
	fi
}

# Turn a record into the editable form: one `field: value` line per field,
# comments on top, the way the secret picker edits an entry. `when` is shown
# the way `add` accepts it, not as the stored ISO string.
edit_form_write() {
	local record="$1" form="$2" id when deadline
	id="$(jq -r '.id' <<<"$record")"
	when="$(jq -r '.when // ""' <<<"$record")"
	[ -n "$when" ] && when="$(date -d "$when" '+%Y-%m-%d %H:%M')"
	deadline="$(jq -r '.deadline // ""' <<<"$record")"
	[ -n "$deadline" ] && deadline="$(date -d "$deadline" '+%Y-%m-%d %H:%M')"
	{
		printf '# %s  [%s]. Edit, save, quit.\n' "$(record_title "$record")" "$id"
		printf '# when     10m 2h 1d 1w, tomorrow, eod, eow, or anything date -d takes\n'
		printf '# repeat   5-field cron or "every 7d"; empty makes it a one-shot\n'
		printf '# deadline when the check must have succeeded or failed, same specs as when\n'
		printf '# on-notify  regex over a popup log record; fires the exec once per match, no when or repeat\n'
		printf '# delay    with on-notify: fire that long after the popup (10m 2h)\n'
		printf '# subject  task:<uuid>, url:<url>, or free text\n'
		printf '# action   show, open, exec\n'
		printf '# command  what exec runs; empty clears it\n'
		printf '# notify   dialog, mail, or silent\n'
		printf '# on-hit   one action after success (exit 2), check output on stdin; repeat lines for more actions\n'
		printf '# on-fail  one action after failure (exit 3), same; only failed actions retry\n'
		printf '# on-miss  shell run after not yet (exit 0), same\n'
		printf 'label: %s\n' "$(jq -r '.label // ""' <<<"$record")"
		printf 'when: %s\n' "$when"
		printf 'repeat: %s\n' "$(jq -r '.repeat // ""' <<<"$record")"
		printf 'deadline: %s\n' "$deadline"
		printf 'on-notify: %s\n' "$(jq -r '.on_notify // ""' <<<"$record")"
		printf 'delay: %s\n' "$(jq -r '.delay // ""' <<<"$record")"
		printf 'subject: %s\n' "$(jq -r '.subject // ""' <<<"$record")"
		printf 'action: %s\n' "$(jq -r '.action // "show"' <<<"$record")"
		printf 'command: %s\n' "$(jq -r '.command // ""' <<<"$record")"
		printf 'notify: %s\n' "$(jq -r '.notify // "dialog"' <<<"$record")"
		action_properties "$record" on_hit 'on-hit: ' 1
		action_properties "$record" on_fail 'on-fail: ' 1
		printf 'on-miss: %s\n' "$(jq -r '.on_miss // ""' <<<"$record")"
	} >"$form"
}

# Read one field back from the saved form, trimmed. A missing line reads as
# empty, which the caller treats as "clear it".
edit_form_field() {
	sed -n "s/^$2:[[:space:]]*//p" "$1" | head -1 | sed 's/[[:space:]]*$//'
}

# Verdict actions are arrays; old strings remain readable without a migration.
record_actions() {
	jq -c --arg field "$2" '.[$field] | if type == "array" then . elif type == "string" and . != "" then [.] else [] end' <<<"$1"
}

# Forms and agendas keep one property per action, in execution order.
action_properties() {
	local actions
	actions="$(record_actions "$1" "$2")"
	if [ "$actions" = '[]' ] && [ "${4:-0}" = 1 ]; then
		printf '%s\n' "$3"
	else
		jq -r --arg prefix "$3" '.[] | $prefix + .' <<<"$actions"
	fi
}

# Read every repeated action property from the editor form.
edit_form_actions() {
	sed -n "s/^$2:[[:space:]]*//p" "$1" | jq -Rsc 'split("\n") | map(select(length > 0))'
}

# Apply raw field values (as typed in a form or an agenda line) to a record.
# Only fields that differ from the record are written, so an untouched line
# changes nothing and an emptied field clears the stored value. Prints
# Updated or Unchanged; the caller syncs the clocks.
edit_apply() {
	local id="$1" label="$2" when="$3" repeat="$4" subject="$5" action="$6" command="$7" notify="${8:-}" on_hit="${9:-}" on_miss="${10:-}" on_notify="${11:-}" delay="${12:-}" deadline="${13:-}" on_fail="${14:-}"
	local record filter='.' cur_when cur_subject
	record="$(get_record "$id")"
	[ -n "$action" ] || action=show
	validate_trigger "$when" "$repeat" "$on_notify" "$delay" "$action"
	cur_when="$(jq -r '.when // ""' <<<"$record")"
	if [ -n "$when" ]; then
		when="$(parse_when "$when")" || die "Cannot parse time: $when"
	fi
	if [ "$when" != "$cur_when" ]; then
		filter="$filter | .when = \$when"
		[ -n "$when" ] && check_off_window "$when" ""
	fi
	if [ "$repeat" != "$(jq -r '.repeat // ""' <<<"$record")" ]; then
		if [ -n "$repeat" ]; then
			repeat="$(parse_repeat "$repeat")" || die "Cannot parse repeat: $repeat"
			check_off_window "" "$repeat"
		fi
		filter="$filter | .repeat = \$repeat"
	fi
	if [ -n "$deadline" ]; then
		deadline="$(parse_when "$deadline")" || die "Cannot parse deadline: $deadline"
	fi
	if [ "$deadline" != "$(jq -r '.deadline // ""' <<<"$record")" ]; then
		filter="$filter | .deadline = \$deadline | del(.deadline_seen, .deadline_retry)"
	fi
	# A multi-line subject is shown by its first line only; matching that
	# first line means it was left alone.
	cur_subject="$(jq -r '.subject // ""' <<<"$record")"
	if [ "$subject" != "$cur_subject" ] && [ "$subject" != "${cur_subject%%$'\n'*}" ]; then
		subject="$(normalize_subject "$subject")"
		filter="$filter | .subject = \$subject"
	else
		subject="$cur_subject"
	fi
	# The title column shows the label, or the subject-derived title when
	# there is none; only a title that moved away from that becomes a label.
	if [ "$label" != "$(jq -r '.label // ""' <<<"$record")" ] && [ "$label" != "$(record_title "$record")" ]; then
		filter="$filter | .label = \$label"
	fi
	[ -n "$action" ] || action=show
	if [ "$action" != "$(jq -r '.action // "show"' <<<"$record")" ] || [ "$command" != "$(jq -r '.command // ""' <<<"$record")" ]; then
		validate_action "$action" "$command"
		filter="$filter | .action = \$action | .command = \$command"
	fi
	[ "$notify" = dialog ] && notify=""
	if [ "$notify" != "$(jq -r '.notify // ""' <<<"$record")" ]; then
		validate_notify "$notify"
		filter="$filter | .notify = \$notify"
	fi
	on_hit="${on_hit:-[]}" on_fail="${on_fail:-[]}"
	[ "$on_hit" != "$(record_actions "$record" on_hit)" ] && filter="$filter | .on_hit = \$on_hit"
	[ "$on_fail" != "$(record_actions "$record" on_fail)" ] && filter="$filter | .on_fail = \$on_fail"
	[ "$on_miss" != "$(jq -r '.on_miss // ""' <<<"$record")" ] && filter="$filter | .on_miss = \$on_miss"
	[ "$on_notify" != "$(jq -r '.on_notify // ""' <<<"$record")" ] && filter="$filter | .on_notify = \$on_notify"
	[ "$delay" != "$(jq -r '.delay // ""' <<<"$record")" ] && filter="$filter | .delay = \$delay"
	if [ "$filter" = '.' ]; then
		printf 'Unchanged %s\n' "$id"
		return 0
	fi
	update_record "$id" "$filter" --arg when "$when" --arg repeat "$repeat" --arg subject "$subject" \
		--arg label "$label" --arg action "$action" --arg command "$command" --arg notify "$notify" \
		--argjson on_hit "$on_hit" --arg on_miss "$on_miss" --arg on_notify "$on_notify" --arg delay "$delay" \
		--arg deadline "$deadline" --argjson on_fail "$on_fail"
	printf 'Updated %s\n' "$id"
}

# `edit <id>` with no options: open the record in $EDITOR, then apply.
cmd_edit_form() {
	local id="$1" record form editor
	record="$(get_record "$id")"
	form="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/remind-edit.XXXXXX")"
	# Expanded now: form is local, so a quoted trap would see it empty at exit.
	# shellcheck disable=SC2064
	trap "rm -f -- $(printf '%q' "$form")" EXIT
	edit_form_write "$record" "$form"
	editor="${REMINDER_EDITOR:-${EDITOR:-nvim}}"
	$editor "$form" || die "Editor exited with $?; nothing changed."
	edit_apply "$id" "$(edit_form_field "$form" label)" "$(edit_form_field "$form" when)" \
		"$(edit_form_field "$form" repeat)" "$(edit_form_field "$form" subject)" \
		"$(edit_form_field "$form" action)" "$(edit_form_field "$form" command)" \
		"$(edit_form_field "$form" notify)" "$(edit_form_actions "$form" on-hit)" "$(edit_form_field "$form" on-miss)" \
		"$(edit_form_field "$form" on-notify)" "$(edit_form_field "$form" delay)" \
		"$(edit_form_field "$form" deadline)" "$(edit_form_actions "$form" on-fail)"
	cmd_sync >/dev/null
}

# ---------------------------------------------------------------- agenda ----
#
# The agenda is the reminder list as an org file: one heading per horizon,
# one line per reminder, org-style <timestamps>. It is written to
# $STATE_DIR/agenda.org, edited in place, and read back: a changed line is an
# edit, a removed line a delete, a line without an id an add. `agenda render`
# and `agenda apply <file>` are the two halves for scripts and agents.

AGENDA="${REMINDER_AGENDA:-$STATE_DIR/agenda.org}"

agenda_stamp() {
	date -d "$1" '+%Y-%m-%d %a %H:%M'
}

# Which heading a record belongs under, from its when relative to today.
agenda_section() {
	local when="$1" repeat="$2" on_notify="${3:-}" day today
	if [ -z "$when" ]; then
		if [ -n "$repeat" ]; then
			printf 'Recurring'
		elif [ -n "$on_notify" ]; then
			printf 'On popup'
		else
			printf 'Unscheduled'
		fi
		return 0
	fi
	day="$(date -d "$when" +%F)"
	today="$(date +%F)"
	if [ "$(date -d "$when" +%s)" -lt "$(date +%s)" ]; then
		printf 'Overdue'
	elif [ "$day" = "$today" ]; then
		printf 'Today'
	elif [ "$day" = "$(date -d 'tomorrow' +%F)" ]; then
		printf 'Tomorrow'
	elif [ "$day" \< "$(date -d '+7 days' +%F)" ]; then
		printf 'This week'
	else
		printf 'Later'
	fi
}

# How the record's last firing ended, from the fire log: the time it fired and
# what followed (verdict, failed hook, dialog answer). Read only, apply skips
# it: the log is the truth for what happened, the store for what should.
agenda_last() {
	local id="$1" last
	[ -f "$FIRE_LOG" ] || return 0
	last="$(fire_history | awk -F '\t' -v id="$id" '
		function add(s) { out = out == "" ? s : out ", " s }
		$2 != id { next }
		$3 == "fired" { at = $1; out = ""; popup = ($4 ~ /on popup/); next }
		$3 == "skipped" || $3 == "stale" { at = $1; out = $3 ": " $4; next }
		$3 == "queued" { at = $1; out = $4; next }
		at == "" { next }
		$3 == "deadline" { at = $1; out = "deadline " $4; next }
		$3 == "exec" { rc = substr($4, 4); add(rc == 0 ? (popup ? "ok" : "no hit") : rc == 2 ? "success" : rc == 3 ? "failure" : "error (exit " rc ")"); next }
		$3 == "on_hit" || $3 == "on_fail" || $3 == "on_miss" {
			rc = substr($4, 4)
			if (rc != 0) add(substr($3, 1, 2) "-" substr($3, 4) " failed (exit " rc ")")
			next
		}
		$3 == "reported" { add("reported: " $4); next }
		$3 == "done" || $3 == "mailed" || $3 == "opened" || $3 == "snoozed" || $3 == "extended" || $3 == "sent" { add($3); next }
		$3 == "dismissed" { add("dismissed (" $4 ")"); next }
		$3 == "error" { add($4); next }
		$3 == "failed" { add("failed: " $4); next }
		END { if (at != "") printf "%s\t%s\n", at, out == "" ? "fired" : out }
	')"
	[ -n "$last" ] || return 0
	printf '   :last: [%s] %s\n' "$(agenda_stamp "${last%%$'\t'*}")" "${last#*$'\t'}"
	[ -f "$RUNS_DIR/$id.log" ] && printf '   :log: %s/%s.log\n' "${RUNS_DIR/#$HOME/\~}" "$id"
	return 0
}

agenda_line() {
	local record="$1" id when repeat action command subject stamps notify on_hit on_fail on_miss on_notify delay deadline
	id="$(jq -r '.id' <<<"$record")"
	when="$(jq -r '.when // ""' <<<"$record")"
	repeat="$(jq -r '.repeat // ""' <<<"$record")"
	on_notify="$(jq -r '.on_notify // ""' <<<"$record")"
	delay="$(jq -r '.delay // ""' <<<"$record")"
	action="$(jq -r '.action // "show"' <<<"$record")"
	command="$(jq -r '.command // ""' <<<"$record")"
	subject="$(jq -r '(.subject // "") | split("\n") | .[0] // ""' <<<"$record")"
	stamps=""
	[ -n "$when" ] && stamps="<$(agenda_stamp "$when")>"
	[ -n "$repeat" ] && stamps="${stamps:+$stamps }<$repeat>"
	printf '** %s%s\n' "${stamps:+$stamps }" "$(record_title "$record")"
	deadline="$(jq -r '.deadline // ""' <<<"$record")"
	[ -n "$deadline" ] && printf '   :deadline: <%s>\n' "$(agenda_stamp "$deadline")"
	[ -n "$on_notify" ] && printf '   :on-notify: %s\n' "$on_notify"
	[ -n "$delay" ] && printf '   :delay: %s\n' "$delay"
	[ "$action" != show ] && printf '   :action: %s\n' "$action"
	[ "$action" = exec ] && printf '   :runs: %s\n' "$command"
	notify="$(jq -r '.notify // ""' <<<"$record")"
	[ -n "$notify" ] && printf '   :notify: %s\n' "$notify"
	action_properties "$record" on_hit '   :on-hit: '
	action_properties "$record" on_fail '   :on-fail: '
	on_miss="$(jq -r '.on_miss // ""' <<<"$record")"
	[ -n "$on_miss" ] && printf '   :on-miss: %s\n' "$on_miss"
	case "$subject" in
	task:*) printf '   :task: %s\n' "${subject#task:}" ;;
	url:*) printf '   :url: %s\n' "${subject#url:}" ;;
	text:*) printf '   :notes: %s\n' "${subject#text:}" ;;
	esac
	agenda_last "$id"
	printf '   :id: %s\n\n' "$id"
	return 0
}

agenda_render() {
	local section record when repeat
	local -a sections=(Overdue Today Tomorrow 'This week' Later Recurring 'On popup' Unscheduled)
	local -A bucket=()
	while IFS= read -r record; do
		[ -n "$record" ] || continue
		when="$(jq -r '.when // ""' <<<"$record")"
		repeat="$(jq -r '.repeat // ""' <<<"$record")"
		section="$(agenda_section "$when" "$repeat" "$(jq -r '.on_notify // ""' <<<"$record")")"
		bucket["$section"]+="$(agenda_line "$record")"$'\n\n'
	done < <(active_records)
	cat <<'HEAD'
#+TITLE: Reminders
# One ** heading per reminder. Edit the text and save: a changed heading is an
# edit, a deleted heading deletes, a new heading adds. Quit without saving and
# nothing happens.
#
#   ** <2026-09-27 Sun 22:00> title      one-shot, 24h clock; any time `date -d` accepts
#   ** <0 9 * * 1> title                 repeat at wall-clock times: 5-field cron
#   ** <every 7d> title                  repeat by interval (m h d w), catches up if
#                                        the laptop was off; <date> <repeat> = snoozed
#   ** title                             no stamp: fires on a popup (see :on-notify:)
#      :deadline: <2026-11-18 Wed 09:00> the check must have settled by then; past it you
#                                        get the form (extend, send to AI, delete)
#      :on-notify: regex                 over a popup log record; runs :runs: once per match
#      :delay: 10m                       with :on-notify:, that long after the popup
#      :action: open | exec              omitted means show a dialog
#      :runs: command                    for exec; exit 0 not yet, 2 success, 3 failure: both
#                                        write a report task and retire it; else an error task
#      :notify: mail | silent            a show goes to a dialog (default), your mail, or
#                                        nowhere; mail also copies an exec verdict
#      :on-hit: shell                    one action after success; repeat the property for more
#                                        actions. Only failed actions retry, without rerunning the check
#      :on-fail: shell                   one action after failure (exit 3), same
#      :on-miss: shell                   runs after not yet (exit 0), e.g. __mail_me.sh "not yet"
#      :task: <uuid>                     what it points at: a task (ctrl+5 opens it),
#      :url: <link>                      a link, or
#      :notes: free text                 notes; one of the three per reminder
#      :last: [date] outcome             read only: how the last firing ended
#      :log: path                        read only: output of recent exec runs (ctrl+2 opens it)
#      :id: 9ed4fac6                     leave it alone; omit on a heading you add
HEAD
	for section in "${sections[@]}"; do
		[ -n "${bucket[$section]:-}" ] || continue
		printf '\n* %s\n\n%s' "$section" "${bucket[$section]}"
	done
}

# Split a heading's text into stamps and title. Sets line_when, line_repeat,
# line_title.
agenda_parse_heading() {
	local rest="$1" token
	line_when="" line_repeat="" line_title=""
	while [[ "$rest" =~ ^\<([^\>]*)\>[[:space:]]*(.*)$ ]]; do
		token="${BASH_REMATCH[1]}"
		rest="${BASH_REMATCH[2]}"
		if parse_repeat "$token" >/dev/null 2>&1; then
			line_repeat="$token"
		else
			line_when="$token"
		fi
	done
	line_title="$(sed 's/[[:space:]]*$//' <<<"$rest")"
}

# Flush the record collected so far (agenda_apply's state) into the store.
agenda_flush() {
	[ -n "$cur_open" ] || return 0
	if [ -n "$cur_id" ]; then
		seen+=("$cur_id")
		edit_apply "$cur_id" "$cur_title" "$cur_when" "$cur_repeat" "$cur_subject" "$cur_action" "$cur_command" "$cur_notify" "$cur_on_hit" "$cur_on_miss" "$cur_on_notify" "$cur_delay" "$cur_deadline" "$cur_on_fail"
	else
		local item
		local -a args=()
		[ -n "$cur_when" ] && args+=(--when "$cur_when")
		[ -n "$cur_repeat" ] && args+=(--repeat "$cur_repeat")
		[ -n "$cur_deadline" ] && args+=(--deadline "$cur_deadline")
		while IFS= read -r item; do args+=(--on-fail "$(jq -r . <<<"$item")"); done < <(jq -c '.[]' <<<"${cur_on_fail:-[]}")
		[ -n "$cur_on_notify" ] && args+=(--on-notify "$cur_on_notify")
		[ -n "$cur_delay" ] && args+=(--delay "$cur_delay")
		[ -n "$cur_subject" ] && args+=(--subject "$cur_subject")
		[ -n "$cur_action" ] && args+=(--action "$cur_action")
		[ -n "$cur_command" ] && args+=(--command "$cur_command")
		[ -n "$cur_notify" ] && args+=(--notify "$cur_notify")
		while IFS= read -r item; do args+=(--on-hit "$(jq -r . <<<"$item")"); done < <(jq -c '.[]' <<<"${cur_on_hit:-[]}")
		[ -n "$cur_on_miss" ] && args+=(--on-miss "$cur_on_miss")
		cmd_add --label "$cur_title" --origin agenda "${args[@]}"
	fi
	cur_open=""
}

# A property line is `   :key: value`; returns key and value through
# prop_key and prop_value.
agenda_prop() {
	[[ "$1" =~ ^[[:space:]]*:([a-z-]+):[[:space:]]*(.*)$ ]] || return 1
	prop_key="${BASH_REMATCH[1]}"
	prop_value="$(sed 's/[[:space:]]*$//' <<<"${BASH_REMATCH[2]}")"
}

agenda_apply() {
	local file="$1" line n=0 id prop_key prop_value
	local cur_open="" cur_id="" cur_title="" cur_when="" cur_repeat="" cur_subject="" cur_action="" cur_command="" cur_notify="" cur_on_hit="" cur_on_miss="" cur_on_notify="" cur_delay="" cur_deadline="" cur_on_fail=""
	local line_when line_repeat line_title
	local -a seen=() active
	[ -f "$file" ] || die "No agenda file at $file."
	# Every line is checked before anything is written, so a typo on line 40
	# does not leave lines 1 to 39 half applied.
	while IFS= read -r line || [ -n "$line" ]; do
		n=$((n + 1))
		case "$line" in
		'' | '#'* | '* '* | '*') continue ;;
		'** '*) ;;
		*)
			agenda_prop "$line" || die "Line $n: cannot read it: $line"
			case "$prop_key" in
			id) get_record "$prop_value" >/dev/null || die "Line $n: no reminder with id $prop_value." ;;
			action | runs | notify | on-hit | on-fail | on-miss | on-notify | delay | deadline | task | url | notes | subject | last | log) ;;
			*) die "Line $n: unknown property :$prop_key:" ;;
			esac
			;;
		esac
	done <"$file"
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
		'' | '#'* | '* '* | '*') continue ;;
		'** '*)
			agenda_flush
			cur_open=1 cur_id="" cur_subject="" cur_command="" cur_action="" cur_notify="" cur_on_hit="" cur_on_miss="" cur_on_notify="" cur_delay="" cur_deadline="" cur_on_fail=""
			agenda_parse_heading "${line#\*\* }"
			cur_when="$line_when" cur_repeat="$line_repeat" cur_title="$line_title"
			;;
		*)
			agenda_prop "$line"
			case "$prop_key" in
			id) cur_id="$prop_value" ;;
			action) cur_action="$prop_value" ;;
			runs) cur_command="$prop_value" ;;
			notify) cur_notify="$prop_value" ;;
			on-hit) cur_on_hit="$(jq -c --arg action "$prop_value" '. + (if $action == "" then [] else [$action] end)' <<<"${cur_on_hit:-[]}")" ;;
			on-fail) cur_on_fail="$(jq -c --arg action "$prop_value" '. + (if $action == "" then [] else [$action] end)' <<<"${cur_on_fail:-[]}")" ;;
			deadline) cur_deadline="$(sed 's/^<\(.*\)>$/\1/' <<<"$prop_value")" ;;
			on-miss) cur_on_miss="$prop_value" ;;
			on-notify) cur_on_notify="$prop_value" ;;
			delay) cur_delay="$prop_value" ;;
			task) cur_subject="task:$prop_value" ;;
			url) cur_subject="url:$prop_value" ;;
			notes) cur_subject="text:$prop_value" ;;
			subject) cur_subject="$prop_value" ;;
			esac
			;;
		esac
	done <"$file"
	agenda_flush
	mapfile -t active < <(active_records | jq -r '.id')
	for id in "${active[@]}"; do
		[[ " ${seen[*]} " == *" $id "* ]] && continue
		update_record "$id" '.status = "deleted"'
		printf 'Deleted %s\n' "$id"
	done
	cmd_sync >/dev/null
}

cmd_agenda() {
	local editor
	case "${1:-}" in
	render) agenda_render ;;
	apply) agenda_apply "${2:-$AGENDA}" ;;
	'')
		agenda_render >"$AGENDA"
		editor="${REMINDER_EDITOR:-${EDITOR:-nvim}}"
		$editor "$AGENDA" || die "Editor exited with $?; nothing changed."
		agenda_apply "$AGENDA"
		;;
	*) die "agenda takes render, apply [file], or nothing." ;;
	esac
}

cmd_edit() {
	local id="$1" filter='.' when repeat subject
	shift
	valid_id "$id" || die "Invalid id $id."
	get_record "$id" >/dev/null || die "No reminder with id $id."
	if [ $# -eq 0 ]; then
		cmd_edit_form "$id"
		return
	fi
	parse_options "$@"
	if [ -n "$opt_when" ]; then
		when="$(parse_when "$opt_when")" || die "Cannot parse time: $opt_when"
		filter="$filter | .when = \"$when\""
		check_off_window "$when" ""
	fi
	if [ -n "$opt_repeat" ]; then
		repeat="$(parse_repeat "$opt_repeat")" || die "Cannot parse repeat: $opt_repeat"
		filter="$filter | .repeat = \$repeat"
		check_off_window "" "$repeat"
	fi
	if [ -n "$opt_subject" ]; then
		subject="$(normalize_subject "$opt_subject")"
		filter="$filter | .subject = \$subject"
	fi
	[ -n "$opt_label" ] && filter="$filter | .label = \$label"
	[ -n "$opt_action" ] && { validate_action "$opt_action" "${opt_command:-$(get_record "$id" | jq -r '.command // ""')}"; filter="$filter | .action = \$action"; }
	[ -n "$opt_command" ] && filter="$filter | .command = \$command"
	[ -n "$opt_notify" ] && { validate_notify "$opt_notify"; filter="$filter | .notify = \$notify"; }
	[ -n "$opt_to" ] && { validate_to "$opt_to"; filter="$filter | .to = \$to"; }
	[ "$opt_on_hit_set" = 1 ] && filter="$filter | .on_hit = \$on_hit"
	[ "$opt_on_fail_set" = 1 ] && filter="$filter | .on_fail = \$on_fail"
	[ -n "$opt_on_miss" ] && filter="$filter | .on_miss = \$on_miss"
	local deadline=""
	if [ -n "$opt_deadline" ]; then
		deadline="$(parse_when "$opt_deadline")" || die "Cannot parse deadline: $opt_deadline"
		filter="$filter | .deadline = \$deadline | del(.deadline_seen, .deadline_retry)"
	fi
	# The merged record must still be one trigger kind: a snooze (--when) on
	# an on-notify record would hand it to the at queue with no popup to pass.
	local cur
	cur="$(get_record "$id")"
	validate_trigger "${when:-$(jq -r '.when // ""' <<<"$cur")}" "${repeat:-$(jq -r '.repeat // ""' <<<"$cur")}" \
		"${opt_on_notify:-$(jq -r '.on_notify // ""' <<<"$cur")}" "${opt_delay:-$(jq -r '.delay // ""' <<<"$cur")}" \
		"${opt_action:-$(jq -r '.action // "show"' <<<"$cur")}"
	[ -n "$opt_on_notify" ] && filter="$filter | .on_notify = \$on_notify"
	[ -n "$opt_delay" ] && filter="$filter | .delay = \$delay"
	update_record "$id" "$filter" --arg repeat "$repeat" --arg subject "$subject" \
		--arg label "$opt_label" --arg action "$opt_action" --arg command "$opt_command" --arg notify "$opt_notify" \
		--argjson on_hit "$opt_on_hit" --arg on_miss "$opt_on_miss" --arg to "$opt_to" \
		--arg on_notify "$opt_on_notify" --arg delay "$opt_delay" \
		--argjson on_fail "$opt_on_fail" --arg deadline "$deadline"
	cmd_sync >/dev/null
	printf 'Updated %s\n' "$id"
}

# A one-shot is spent; a repeat drops its pending one-shot (a snooze) only.
# A repeat keeps its schedule and loses only the pending one-shot. One filter,
# so the repeat check and the write see the same record.
mark_done() {
	update_record "$1" 'if (.repeat // "") != "" then del(.when) else .status = "done" | del(.when) end'
}

cmd_done() {
	local id="$1"
	valid_id "$id" || die "Invalid id $id."
	mark_done "$id"
	cmd_sync >/dev/null
	log_fire "$id" "done" manual "$(record_title "$(get_record "$id")")"
}

cmd_delete() {
	local id="$1"
	valid_id "$id" || die "Invalid id $id."
	update_record "$id" '.status = "deleted"'
	cmd_sync >/dev/null
	printf 'Deleted %s\n' "$id"
}

cmd_list() {
	local json=0 all=0 records
	while [ $# -gt 0 ]; do
		case "$1" in
		--json) json=1 ;;
		--all) all=1 ;;
		*) die "Unknown option $1" ;;
		esac
		shift
	done
	if [ "$all" -eq 1 ]; then
		records="$(current_records)"
	else
		records="$(active_records)"
	fi
	if [ "$json" -eq 1 ]; then
		list_json "$records"
		return 0
	fi
	local record id when repeat action title on_notify delay deadline by
	while IFS= read -r record; do
		[ -n "$record" ] || continue
		id="$(jq -r '.id' <<<"$record")"
		when="$(jq -r '.when // ""' <<<"$record")"
		repeat="$(jq -r '.repeat // ""' <<<"$record")"
		on_notify="$(jq -r '.on_notify // ""' <<<"$record")"
		delay="$(jq -r '.delay // ""' <<<"$record")"
		deadline="$(jq -r '.deadline // ""' <<<"$record")"
		action="$(jq -r '.action' <<<"$record")"
		title="$(record_title "$record")"
		by="${deadline:+by $(human_when "$deadline")}"
		if [ -n "$on_notify" ]; then
			printf '%s  %-16s  %-14s  %-19s  %-5s  %s\n' "$id" "on popup" "${delay:++$delay}" "$by" "$action" "$title"
		else
			printf '%s  %-16s  %-14s  %-19s  %-5s  %s\n' "$id" "${when:+$(human_when "$when")}" "$repeat" "$by" "$action" "$title"
		fi
	done <<<"$records"
}

# Records plus derived fields UIs need: a live title, the openable url, and
# whether the one-shot time has passed. Consumers never touch subjects.
list_json() {
	local records="$1" record title url when overdue now
	now="$(date +%s)"
	while IFS= read -r record; do
		[ -n "$record" ] || continue
		title="$(record_title "$record")"
		url="$(subject_url "$(jq -r '.subject // ""' <<<"$record")")" || url=""
		when="$(jq -r '.when // ""' <<<"$record")"
		overdue=false
		[ -n "$when" ] && [ "$(epoch_of "$when")" -lt "$now" ] && overdue=true
		jq -c --arg title "$title" --arg url "$url" --argjson overdue "$overdue" \
			'. + {title: $title, url: $url, overdue: $overdue}' <<<"$record"
	done <<<"$records" | jq -s .
}

# Rewrite the store to one line per id, the current record, filtered by $1.
rewrite_store() {
	prepare_store
	lock_store
	jq -c -s "reduce .[] as \$r ({}; .[\$r.id] = \$r) | .[] | $1" "$STORE" >"$STORE.tmp"
	mv "$STORE.tmp" "$STORE"
	unlock_store
}

# A fire lock outlives its dialog as an empty file. Drop the ones whose
# reminder can no longer fire, and only while nobody holds them: an open
# dialog keeps its lock, so cleanup never lets a second dialog in.
drop_stale_locks() {
	local lock id active
	active="$(active_records | jq -r '.id')"
	for lock in "$STATE_DIR"/fire-*.lock; do
		[ -f "$lock" ] || continue
		id="${lock##*/fire-}"
		id="${id%.lock}"
		grep -qxF "$id" <<<"$active" && continue
		flock -n "$lock" rm -f "$lock" && printf 'lock: dropped %s\n' "${lock##*/}"
	done
	return 0
}

# A match file outlives its at job only when atd dropped the job; a day is
# longer than any delay in use.
drop_stale_matches() {
	[ -d "$MATCH_DIR" ] || return 0
	find "$MATCH_DIR" -type f -mmin +1440 -delete 2>/dev/null || true
}

# gc forgets done and deleted reminders.
cmd_gc() {
	rewrite_store 'select(.status == "active")'
	printf 'Compacted to %s active records.\n' "$(sed -n '$=' "$STORE" || echo 0)"
	drop_stale_locks
	drop_stale_matches
}

# compact forgets only superseded lines: every id keeps its current record,
# done and deleted included, so nothing a reader sees changes. Runs at boot.
cmd_compact() {
	rewrite_store '.'
	printf 'Compacted to %s records.\n' "$(sed -n '$=' "$STORE" || echo 0)"
	drop_stale_locks
}

# ----------------------------------------------------------------- fire ----

# The form behind a show reminder and a passed deadline (kind show or
# deadline). The GUI only names the choice; every consequence is here. Open
# loops back to the form. Extend moves the reminder's time, or the deadline;
# Send to AI hands the state report to Gordon or a new Claude; Delete deletes;
# Done (show only) spends it. Closing without a choice leaves the provisional
# retry the caller set, so the form comes back.
show_dialog() {
	local id="$1" record="$2" title="$3" body="$4" url="$5" due="$6" late="$7" kind="${8:-show}"
	local subject repeat response action when pick
	subject="$(jq -r '.subject // ""' <<<"$record")"
	repeat="$(jq -r '.repeat // ""' <<<"$record")"
	pick="$(date -d 'tomorrow 9:00' '+%Y-%m-%d %H:%M')"

	while true; do
		response="$(jq -nc --arg title "$title" --arg body "$body" --arg url "$url" \
			--arg due "$due" --arg late "$late" --arg type "$(subject_type "$subject")" --arg repeat "$repeat" \
			--arg kind "$kind" --arg pick "$pick" \
			'{kind:$kind, title:$title, body:$body, url:$url, due:$due, late:$late, subject_type:$type, repeat:$repeat, pick:$pick}' \
			| "$GUI" alert)" || {
			log_fire "$id" dismissed "snooze $DEFAULT_SNOOZE" "$title"
			return 0
		}
		action="$(jq -r '.action // ""' <<<"$response")"
		case "$action" in
		open)
			case "$subject" in
			task:*) "$TASK_OPENER" "$subject" >/dev/null 2>&1 || true ;;
			*) [ -n "$url" ] && { open_url "$url" || true; } ;;
			esac
			;;
		done)
			[ "$kind" = show ] || continue
			case "$subject" in
			task:*) task rc.verbose=nothing "${subject#task:}" "done" >/dev/null 2>&1 || true ;;
			esac
			mark_done "$id"
			cmd_sync >/dev/null
			log_fire "$id" "done" "$action" "$title"
			return 0
			;;
		extend | snooze)
			when="$(jq -r '.when // ""' <<<"$response")"
			when="$(parse_when "$when")" || when="$(parse_when "$DEFAULT_SNOOZE")"
			if [ "$kind" = deadline ]; then
				update_record "$id" '.deadline = $when | del(.deadline_retry, .deadline_seen)' --arg when "$when"
				log_fire "$id" extended "$when" "$title"
			else
				update_record "$id" '.when = $when' --arg when "$when"
				log_fire "$id" snoozed "$when" "$title"
			fi
			cmd_sync >/dev/null
			return 0
			;;
		ai)
			send_to_ai "$id" "$title" "$body" "$kind" || return 0
			if [ "$kind" = deadline ]; then
				update_record "$id" '.deadline_seen = .deadline | del(.deadline_retry)'
			else
				mark_done "$id"
			fi
			cmd_sync >/dev/null
			return 0
			;;
		delete)
			update_record "$id" '.status = "deleted"'
			cmd_sync >/dev/null
			log_fire "$id" deleted "from the $kind form" "$title"
			return 0
			;;
		*)
			log_fire "$id" dismissed "snooze $DEFAULT_SNOOZE" "$title"
			return 0
			;;
		esac
	done
}

# ------------------------------------------------------------ send to AI ---

# Gordon's pane: the bus agent `triage` (or `gordon`) a tmux pane carries in
# @agent_name. Prints "<pane_id> <agent>" or nothing.
gordon_pane() {
	"$TMUX_BIN" list-panes -a -F '#{pane_id} #{@agent_name}' 2>/dev/null |
		awk '$2 == "triage" || $2 == "gordon" { print $1, $2; exit }'
}

ai_prompt() {
	local id="$1" title="$2" report="$3" kind="$4" ask
	if [ "$kind" = deadline ]; then
		ask="Its deadline passed with neither the success nor the failure condition met. Work with Piotr on its conditions: change the check, extend the deadline (remind edit $id --deadline <when>), or delete it."
	else
		ask="Work with Piotr on what it asks for, then mark it done or move it (remind edit $id --when <when>)."
	fi
	printf 'Piotr sent reminder %s to you from its form: %s\n\n%s\n\n%s Load the reminder skill; `remind list --json | jq '"'"'.[] | select(.id == "%s")'"'"'` shows the record.' \
		"$id" "$title" "$report" "$ask" "$id"
}

# Gordon when his pane is up: a DM on the agents bus, then Piotr's terminal
# moves to that pane so the conversation is in front of him. Otherwise, or
# when the DM fails, a new Claude window in the attached tmux session.
send_to_ai() {
	local id="$1" title="$2" report="$3" kind="$4" prompt pane="" agent="" client session
	prompt="$(ai_prompt "$id" "$title" "$report" "$kind")"
	read -r pane agent < <(gordon_pane) || true
	client="$("$TMUX_BIN" list-clients -F '#{client_name}' 2>/dev/null | head -n1)" || true
	if [ -n "$pane" ] && SND_FROM=reminder timeout 20 "$SND" --no-human -t "$agent" "${prompt:0:1500}" >/dev/null 2>&1; then
		if [ -n "$client" ]; then
			"$TMUX_BIN" switch-client -c "$client" -t "$pane" >/dev/null 2>&1 || true
			"$TMUX_BIN" select-window -t "$pane" >/dev/null 2>&1 || true
			"$TMUX_BIN" select-pane -t "$pane" >/dev/null 2>&1 || true
		fi
		log_fire "$id" sent "gordon ($agent)" "$title"
		return 0
	fi
	if [ -n "$client" ]; then
		session="$("$TMUX_BIN" display-message -p -c "$client" '#{session_name}' 2>/dev/null)" || session=""
		if "$TMUX_BIN" new-window ${session:+-t "$session:"} -c "$AI_CWD" -n "remind-$id" -- "$CLAUDE_LAUNCHER" "$prompt" >/dev/null 2>&1; then
			log_fire "$id" sent "new claude window" "$title"
			return 0
		fi
	fi
	log_fire "$id" error "send to AI: no Gordon pane and no tmux client for a new Claude" "$title"
	show_error "Could not send reminder $id to an AI: Gordon is not running and no tmux client is attached for a new Claude window."
	return 1
}

# Provisional snooze, one-dialog lock, then the dialog decides. The snooze
# comes first so a dialog that dies with the session brings the reminder back
# instead of losing it. The lock keeps one dialog per reminder: the snooze
# re-fires while an unanswered dialog is still on screen (measured: 15 minutes
# away from the desk produced two dialogs), so a fire that finds the lock held
# only refreshed the snooze and leaves the open dialog to decide.
# Hand a fired reminder to Gordon: one line in the notification log in the
# logger's format (time, app, summary, body, tab separated). One printf into an
# O_APPEND file, capped under PIPE_BUF, so it cannot interleave with the
# logger. Returns non-zero when the append fails, so callers fall back to the
# dialog and nothing is lost. The body leads with id:<id> | , the metadata
# form the events shipper reads, so intake's s finds the reminder.
notify_gordon() {
	local id="$1" title="$2" body="$3" summary line
	summary="$(printf '%s' "$title" | tr '\t\n' '  ')"
	body="id:$id | $(printf '%s' "$body" | tr '\t\n' '  ' | head -c 3000)"
	line="$(printf '%s\t%s\t%s\t%s' "$(date '+%F %T')" reminder "$summary" "$body")"
	printf '%s\n' "$line" >>"$NOTIFY_LOG" 2>/dev/null
}

record_to() {
	jq -r '.to // "piotr"' <<<"$1"
}

guarded_dialog() {
	local id="$1" record="$2" title="$3" body="$4" url="$5" due="$6" late="$7"
	local snooze_until
	snooze_until="$(parse_when "$DEFAULT_SNOOZE")"
	update_record "$id" '.when = $when | .last_fired = $now' \
		--arg when "$snooze_until" --arg now "$(now_iso)"
	cmd_sync >/dev/null
	mkdir -p "$STATE_DIR"
	exec 8>"$STATE_DIR/fire-$id.lock"
	if ! flock -n 8; then
		log_fire "$id" skipped "dialog already open, snoozed to $snooze_until" "$title"
		return 0
	fi
	show_dialog "$id" "$record" "$title" "$body" "$url" "$due" "$late"
	flock -u 8
}

RUNS_DIR="$STATE_DIR/runs"
RUN_LOG_LINES="${REMINDER_RUN_LOG_LINES:-2000}"

# Append one exec run to the reminder's run log: the check's command, exit
# and output, then the hook's if one ran. The fire log keeps only exit codes
# and the mail lands in an inbox, so this file is where the why stays readable.
# Trimmed to the newest RUN_LOG_LINES so a daily check cannot grow it forever.
log_run() {
	local id="$1" rc="$2" command="$3" output="$4" field="$5" hook="$6" hrc="$7" hook_output="$8" file
	mkdir -p "$RUNS_DIR"
	file="$RUNS_DIR/$id.log"
	{
		printf '=== %s exit %s\n$ %s\n' "$(now_iso)" "$rc" "$command"
		[ -n "$output" ] && printf '%s\n' "$output"
		if [ -n "$hook" ]; then
			printf -- '--- %s exit %s\n$ %s\n' "${field//_/-}" "$hrc" "$hook"
			[ -n "$hook_output" ] && printf '%s\n' "$hook_output"
		fi
	} >>"$file"
	tail -n "$RUN_LOG_LINES" "$file" >"$file.tmp" && mv "$file.tmp" "$file"
}

# The branch after a check: on_hit after exit 2, on_fail after exit 3,
# on_miss after exit 0, the check's output on stdin. Plain shell, so
# `y.sh && __mail_me.sh "done"` chains. A hook that fails turns the run into
# an execution error (cmd_fire); it is logged here.
run_branch() {
	local id="$1" record="$2" rc="$3" output="$4" title="$5" hook field hrc=0
	case "$rc" in
	2) field=on_hit ;;
	3) field=on_fail ;;
	0) field=on_miss ;;
	*) return 0 ;;
	esac
	hook="$(jq -r ".$field // \"\"" <<<"$record")"
	[ -n "$hook" ] || return 0
	BRANCH_HOOK="$hook" BRANCH_FIELD="$field"
	BRANCH_OUTPUT="$(printf '%s\n' "$output" | bash -c "$hook" 6>&- 2>&1)" || hrc=$?
	BRANCH_RC="$hrc"
	log_fire "$id" "$field" "rc=$hrc" "$title"
}

# Save the check verdict before any action. Later fires use this evidence and
# action list even if the check or configured hooks have since changed.
latch_verdict() {
	local id="$1" record="$2" rc="$3" output="$4" field=on_hit outcome=success
	if [ "$rc" = 3 ]; then field=on_fail; outcome=failure; fi
	update_record "$id" '.verdict = {rc:$rc, outcome:$outcome, output:$output,
		command:$command, field:$field, actions:($actions | map({command:., status:"pending", attempts:0, history:[]}))}' \
		--argjson rc "$rc" --arg outcome "$outcome" --arg output "$output" \
		--arg command "$(jq -r '.command' <<<"$record")" --arg field "$field" \
		--argjson actions "$(record_actions "$record" "$field")"
}

# Run unfinished verdict actions in order. Each result is durable before the
# next action starts; a failure never stops later actions or repeats a done one.
run_latched_actions() {
	local id="$1" title="$2" record action command output check_output field index count rc
	record="$(get_record "$id")"
	check_output="$(jq -r '.verdict.output' <<<"$record")"
	field="$(jq -r '.verdict.field' <<<"$record")"
	count="$(jq '.verdict.actions | length' <<<"$record")"
	BRANCH_RC=0 BRANCH_OUTPUT="" BRANCH_FIELD="$field"
	for ((index=0; index<count; index++)); do
		action="$(jq -c --argjson index "$index" '.verdict.actions[$index]' <<<"$record")"
		[ "$(jq -r '.status' <<<"$action")" != "done" ] || continue
		command="$(jq -r '.command' <<<"$action")"
		rc=0
		output="$(printf '%s\n' "$check_output" | REMINDER_ID="$id" bash -c "$command" 6>&- 2>&1)" || rc=$?
		update_record "$id" '.verdict.actions[$index] |= (.attempts += 1 |
			.rc = $rc | .output = $output | .last_line = $last_line |
			.status = (if $rc == 0 then "done" else "failed" end) |
			.history += [{attempt:.attempts, rc:$rc, output:$output}])' \
			--argjson index "$index" --argjson rc "$rc" --arg output "$output" --arg last_line "$(error_reason "$output")"
		log_fire "$id" "$field" "rc=$rc" "$title"
		log_run "$id" "$(jq -r '.verdict.rc' <<<"$record")" "$(jq -r '.verdict.command' <<<"$record")" "$check_output" "$field" "$command" "$rc" "$output"
		if [ "$rc" -ne 0 ] && [ "$BRANCH_RC" = 0 ]; then
			BRANCH_RC="$rc" BRANCH_OUTPUT="$output"
		fi
	done
}

# How long a check has been failing, from the fire log: nothing for a first
# error, "7 errors in a row since <first>" once it repeats. A 0 or 2 verdict
# ends a streak.
error_streak() {
	fire_history | awk -F '\t' -v id="$1" '
		$2 != id || $3 != "exec" { next }
		$4 == "rc=0" || $4 == "rc=2" || $4 == "rc=3" { n = 0; next }
		{ if (n++ == 0) since = $1 }
		END { if (n > 1) printf "%d errors in a row since %s", n, since }
	'
}

# The line that says why a check failed: its last non-empty output line, one
# line and bounded so the fire log stays one record per line. The full output
# is in the run log.
error_reason() {
	printf '%s\n' "$1" | tr '\t' ' ' | sed '/^[[:space:]]*$/d' | tail -n1 | cut -c1-300
}

# --------------------------------------------------------------- reports ---

REPORT_DIR="$STATE_DIR/reports"

# A task, and its uuid on stdout. The description travels as one argv element
# after `--`, never through a shell string.
task_add() {
	local description="$1" out uuid
	shift
	out="$(task rc.verbose=new-uuid rc.confirmation=off add "$@" -- "$description" 2>&1)" || {
		printf '%s\n' "$out" >&2
		return 1
	}
	uuid="$(grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' <<<"$out" | head -n1)"
	[ -n "$uuid" ] || {
		printf 'task add printed no uuid: %s\n' "$out" >&2
		return 1
	}
	printf '%s' "$uuid"
}

task_note() {
	task rc.verbose=nothing rc.confirmation=off "$1" annotate -- "$2" >/dev/null 2>&1
}

# Board titles stay under 60 characters.
short_title() {
	printf '%s' "$1" | tr '\n\t' '  ' | cut -c1-"$2"
}

home_path() {
	printf '%s' "${1/#$HOME/\~}"
}

record_trigger() {
	jq -r 'if (.on_notify // "") != "" then "on popup /" + .on_notify + "/"
		elif (.repeat // "") != "" then "repeat " + .repeat
		elif (.when // "") != "" then "at " + .when else "none" end' <<<"$1"
}

# The trace of a finished packet: what it was, the check and its verdict,
# the action that ran, the fire history and where the logs are. Written before
# the report task, so a failed task write still leaves the trace.
write_trace() {
	local record="$1" outcome="$2" rc="$3" output="$4" field="$5" hook="$6" hrc="$7" houtput="$8" id file
	id="$(jq -r '.id' <<<"$record")"
	mkdir -p "$REPORT_DIR/$id"
	file="$REPORT_DIR/$id/brief.md"
	{
		printf '# %s\n\n' "$(record_title "$record")"
		printf -- '- Reminder: %s\n' "$id"
		printf -- '- Outcome: %s (exit %s)\n' "$outcome" "$rc"
		printf -- '- Finished: %s\n' "$(now_iso)"
		printf -- '- Created: %s by %s\n' "$(jq -r '.created // "?"' <<<"$record")" "$(jq -r '.origin // "?"' <<<"$record")"
		printf -- '- Trigger: %s\n' "$(record_trigger "$record")"
		printf -- '- Deadline: %s\n' "$(jq -r '.deadline // "none"' <<<"$record")"
		printf -- '- Subject: %s\n' "$(jq -r '.subject // "none"' <<<"$record")"
		printf '\n## Check\n\n```\n$ %s\n%s\n```\n' "$(jq -r '.verdict.command // .command // ""' <<<"$record")" "$output"
		if [ "$(jq '.verdict.actions // [] | length' <<<"$record")" -gt 0 ]; then
			local entry action attempt
			while IFS= read -r entry; do
				action="$(jq -c '.value' <<<"$entry")"
				printf '\n## Action %s: %s (%s, attempts %s)\n\n```\n$ %s\n```\n' \
					"$(jq '.key + 1' <<<"$entry")" "${field//_/-}" "$(jq -r '.status' <<<"$action")" \
					"$(jq '.attempts' <<<"$action")" "$(jq -r '.command' <<<"$action")"
				while IFS= read -r attempt; do
					printf '\n### Attempt %s (exit %s)\n\n```\n%s\n```\n' "$(jq '.attempt' <<<"$attempt")" "$(jq '.rc' <<<"$attempt")" "$(jq -r '.output' <<<"$attempt")"
				done < <(jq -c '.history[]' <<<"$action")
				printf '\nLast output: %s\n' "$(jq -r '.last_line // ""' <<<"$action")"
			done < <(jq -c '.verdict.actions | to_entries[]' <<<"$record")
		elif [ -n "$hook" ]; then
			printf '\n## Action: %s (exit %s)\n\n```\n$ %s\n%s\n```\n' "${field//_/-}" "$hrc" "$hook" "$houtput"
		else
			printf '\n## Action\n\nNone: the check itself was the whole packet.\n'
		fi
		printf '\n## History\n\n```\n'
		fire_history | awk -F '\t' -v id="$id" '$2 == id' | tail -n 40
		printf '```\n\n## Logs\n\n- Runs: %s\n- Fire log: %s\n' "$(home_path "$RUNS_DIR/$id.log")" "$(home_path "$FIRE_LOG")"
	} >"$file"
	printf '%s' "$file"
}

# The report task every finished packet leaves for Piotr and Gordon. Prints
# its uuid.
report_task() {
	local record="$1" outcome="$2" trace="$3" output="$4" id title uuid url first
	id="$(jq -r '.id' <<<"$record")"
	title="$(record_title "$record")"
	uuid="$(task_add "$(short_title "packet-report: $title" 60)" "tags:work,reminder,packet-report,$outcome")" || return 1
	first="$(printf '%s\n' "$output" | sed '/^[[:space:]]*$/d' | head -n2 | tr '\n' ' ' | cut -c1-300)"
	task_note "$uuid" "what: Reminder $id finished with $outcome: $title. Its actions already ran; this task is the report."
	task_note "$uuid" "brief: ${first:-The check printed nothing.} The trace lists the check, the action and every run. Read it, then close this task."
	task_note "$uuid" "trace: $(home_path "$trace")"
	url="$(subject_url "$(jq -r '.subject // ""' <<<"$record")")" && task_note "$uuid" "link: $url"
	printf '%s' "$uuid"
}

# A packet completes once. The report task must exist before it retires: a
# failed write keeps the record active with report_pending, and the next fire
# retries the write without running the check or its action again (a one-shot
# gets its retry time here).
complete_packet() {
	local id="$1" outcome="$2" trace="$3" output="$4" record title uuid err
	record="$(get_record "$id")"
	title="$(record_title "$record")"
	err="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/remind-report.XXXXXX")"
	if uuid="$(report_task "$record" "$outcome" "$trace" "$output" 2>"$err")"; then
		update_record "$id" '.status = "done" | .report_task = $uuid
			| del(.when, .repeat, .report_pending, .report_outcome, .deadline_retry)' --arg uuid "$uuid"
		log_fire "$id" reported "$outcome task $uuid" "$title"
	else
		update_record "$id" '.report_pending = $trace | .report_outcome = $outcome
			| if (.repeat // "") == "" then .when = $retry else . end' \
			--arg trace "$trace" --arg outcome "$outcome" --arg retry "$(parse_when "$DEFAULT_SNOOZE")"
		log_fire "$id" error "report task failed: $(error_reason "$(cat "$err")")" "$title"
	fi
	rm -f "$err"
	cmd_sync >/dev/null
}

# One open task per failing packet, for Gordon or another AI. A new reason
# annotates it; the same reason again only counts in the fire log, so a check
# failing every 30 minutes leaves one task with one note per distinct failure.
error_task() {
	local id="$1" title="$2" reason="$3" record uuid status
	record="$(get_record "$id")"
	uuid="$(jq -r '.error_task // ""' <<<"$record")"
	if [ -n "$uuid" ]; then
		status="$(task_field "$uuid" status)"
		if [ "$status" = pending ] || [ "$status" = waiting ]; then
			[ "$reason" != "$(jq -r '.error_reason // ""' <<<"$record")" ] || return 0
			task_note "$uuid" "error again $(now_iso): $reason" || true
			update_record "$id" '.error_reason = $reason' --arg reason "$reason"
			return 0
		fi
	fi
	uuid="$(task_add "$(short_title "$id ($title" 52)) error" +gordon +work +reminder 2>/dev/null)" || {
		log_fire "$id" error "could not write the error task" "$title"
		return 0
	}
	task_note "$uuid" "what: Reminder $id ($title) failed to run: $reason. Read the run log, fix the check or its action, then close this task."
	task_note "$uuid" "log: $(home_path "$RUNS_DIR/$id.log")"
	update_record "$id" '.error_task = $uuid | .error_reason = $reason' --arg uuid "$uuid" --arg reason "$reason"
	log_fire "$id" error-task "$uuid" "$title"
}

# A clean run after errors: one note on the open error task. A packet that keeps
# running passes keep and holds on to the task, so its next failure adds to it
# and a flaky network cannot stack open tasks. A retiring packet forgets it.
clear_error_task() {
	local id="$1" keep="${2:-}" record uuid reason
	record="$(get_record "$id")"
	uuid="$(jq -r '.error_task // ""' <<<"$record")"
	reason="$(jq -r '.error_reason // ""' <<<"$record")"
	[ -n "$uuid" ] || return 0
	[ -n "$reason" ] || [ -z "$keep" ] || return 0
	[ -z "$reason" ] || task_note "$uuid" "recovered $(now_iso): the check ran clean again" || true
	if [ -n "$keep" ]; then
		update_record "$id" 'del(.error_reason)'
	else
		update_record "$id" 'del(.error_task, .error_reason)'
	fi
}

# Exec packets serialize the whole fire, including report creation. A second
# clock skips immediately; the state is read again only after taking the lock.
# Plain reminder dialogs keep their existing snooze and dialog-lock behavior.
cmd_fire() {
	local id="$1" record rc=0
	valid_id "$id" || die "Invalid id $id."
	record="$(get_record "$id")" || { cmd_fire_locked "$@"; return; }
	if [ "$(jq -r '.action' <<<"$record")" != exec ]; then
		cmd_fire_locked "$@"
		return
	fi
	mkdir -p "$STATE_DIR"
	exec 6>"$STATE_DIR/execute-$id.lock"
	if ! flock -n 6; then
		log_fire "$id" skipped "packet already running" "$(record_title "$record")"
		exec 6>&-
		return 0
	fi
	cmd_fire_locked "$@"
	flock -u 6
	exec 6>&-
	return "$rc"
}

cmd_fire_locked() {
	local id="$1" record status action subject type title body url due late command notify
	valid_id "$id" || die "Invalid id $id."
	export DISPLAY="${DISPLAY:-:0}"
	export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"

	record="$(get_record "$id")" || {
		log_fire "$id" missing "" ""
		return 0
	}
	status="$(jq -r '.status' <<<"$record")"
	title="$(record_title "$record")"
	if [ "$status" != active ]; then
		log_fire "$id" skipped "status $status" "$title"
		return 0
	fi
	if [ -n "$(jq -r '.on_notify // ""' <<<"$record")" ]; then
		fire_on_notify "$id" "$record" "$title" "${2:-}"
		return 0
	fi

	subject="$(jq -r '.subject // ""' <<<"$record")"
	type="$(subject_type "$subject")"
	if [ "$type" = task ] && [ "$(jq '.verdict == null' <<<"$record")" = true ]; then
		status="$(task_field "${subject#task:}" status)"
		case "$status" in
		pending | waiting) ;;
		*)
			log_fire "$id" skipped "task ${status:-gone}" "$title"
			mark_done "$id"
			cmd_sync >/dev/null
			return 0
			;;
		esac
	fi
	body="$(subject_body "$subject")"
	url="$(subject_url "$subject")" || url=""

	due="$(jq -r '.when // ""' <<<"$record")"
	late=""
	if [ -n "$due" ]; then
		local late_s=$(($(date +%s) - $(epoch_of "$due")))
		[ "$late_s" -gt "$LATE_AFTER" ] && late="$(human_duration "$late_s")"
	fi
	action="$(jq -r '.action' <<<"$record")"
	log_fire "$id" fired "${action}${due:+ due $due}${late:+ late $late}" "$title"

	case "$action" in
	show)
		notify="$(jq -r '.notify // "dialog"' <<<"$record")"
		if [ "$(record_to "$record")" = gordon ] && notify_gordon "$id" "$title" "$body${url:+ $url}"; then notify=gordon; fi
		case "$notify" in
		gordon)
			mark_done "$id"
			cmd_sync >/dev/null
			log_fire "$id" delivered gordon "$title"
			;;
		mail)
			printf '%s\n%s\n' "$body" "${url:+$url}" | "$MAILER" "$title"
			mark_done "$id"
			cmd_sync >/dev/null
			log_fire "$id" mailed "$title" "$title"
			;;
		*) guarded_dialog "$id" "$record" "$title" "$body" "$url" "${due:+$(human_when "$due")}" "$late" ;;
		esac
		;;
	open)
		update_record "$id" '.last_fired = $now' --arg now "$(now_iso)"
		if [ -n "$url" ]; then
			if open_url "$url"; then
				log_fire "$id" opened "$url" "$title"
			else
				log_fire "$id" failed "open $url" "$title"
			fi
		else
			log_fire "$id" failed "no url" "$title"
		fi
		mark_done "$id"
		cmd_sync >/dev/null
		;;
	exec)
		# The exit code is the verdict, the same channel __cron_run.sh reads:
		# 0 not yet (silent), 2 success, 3 failure, anything else an execution
		# error. Success and failure complete the packet (complete_packet);
		# an error, or a hook that fails, opens the error task and keeps the
		# schedule so the next run can succeed. Nothing here opens a dialog:
		# a verdict is a task, never a popup.
		update_record "$id" '.last_fired = $now' --arg now "$(now_iso)"
		if [ -n "$(jq -r '.report_pending // ""' <<<"$record")" ]; then
			complete_packet "$id" "$(jq -r '.report_outcome // "success"' <<<"$record")" "$(jq -r '.report_pending' <<<"$record")" ""
			return 0
		fi
		local rc=0 output
		if [ "$(jq '.verdict != null' <<<"$record")" = true ]; then
			command="$(jq -r '.verdict.command' <<<"$record")"
			rc="$(jq -r '.verdict.rc' <<<"$record")"
			output="$(jq -r '.verdict.output' <<<"$record")"
		else
			command="$(jq -r '.command // ""' <<<"$record")"
			# bash exits 2 on a syntax error, which would read as a success verdict.
			if ! output="$(bash -n -c "$command" 2>&1)"; then
				rc=1
			else
				output="$(REMINDER_ID="$id" bash -c "$command" 6>&- 2>&1)" || rc=$?
			fi
			log_fire "$id" exec "rc=$rc" "$title"
			if [ "$rc" = 2 ] || [ "$rc" = 3 ]; then
				latch_verdict "$id" "$record" "$rc" "$output"
			fi
		fi
		notify="$(jq -r '.notify // ""' <<<"$record")"
		BRANCH_RC=0 BRANCH_OUTPUT="" BRANCH_HOOK="" BRANCH_FIELD=""
		local trace=""
		if [ "$rc" = 2 ] || [ "$rc" = 3 ]; then
			run_latched_actions "$id" "$title"
			record="$(get_record "$id")"
			trace="$(write_trace "$record" "$(jq -r '.verdict.outcome' <<<"$record")" "$rc" "$output" "$BRANCH_FIELD" "" "$BRANCH_RC" "$BRANCH_OUTPUT")"
			if [ "$(jq '.verdict.actions | length' <<<"$record")" = 0 ]; then
				log_run "$id" "$rc" "$command" "$output" "" "" 0 ""
			fi
		else
			run_branch "$id" "$record" "$rc" "$output" "$title"
			log_run "$id" "$rc" "$command" "$output" "$BRANCH_FIELD" "$BRANCH_HOOK" "$BRANCH_RC" "$BRANCH_OUTPUT"
		fi
		# A verdict whose hook failed is an execution error: the condition held
		# but the action did not happen, so the schedule stays for a retry.
		local verdict="$rc" err_label="exit $rc"
		if [ "$BRANCH_RC" -ne 0 ]; then
			verdict=hook_failed
			err_label="${BRANCH_FIELD//_/-} exit $BRANCH_RC"
			output="$BRANCH_OUTPUT"$'\n---\n'"$output"
		fi
		local streak reason outcome
		if [ "$verdict" = 4 ]; then
			case "$(error_reason "$output")" in
			withdrawn:*) ;;
			*) verdict=error ;;
			esac
		fi
		case "$verdict" in
		0)
			clear_error_task "$id" keep
			mark_done "$id"
			cmd_sync >/dev/null
			;;
		4)
			clear_error_task "$id"
			update_record "$id" '.status = "done" | del(.when, .repeat, .report_pending, .report_outcome, .deadline_retry)'
			reason="$(error_reason "$output")"
			log_fire "$id" withdrawn "${reason#withdrawn: }" "$title"
			cmd_sync >/dev/null
			;;
		2 | 3)
			clear_error_task "$id"
			outcome=success
			[ "$verdict" -eq 3 ] && outcome=failure
			if [ "$(record_to "$record")" = gordon ] && notify_gordon "$id" "$outcome: $title" "$output"; then
				log_fire "$id" delivered gordon "$title"
			fi
			if [ "$notify" = mail ]; then
				printf '%s\n' "$output" | "$MAILER" "$outcome: $title"
				log_fire "$id" mailed "$outcome" "$title"
			fi
			complete_packet "$id" "$outcome" "$trace" "$output"
			;;
		*)
			streak="$(error_streak "$id")"
			if [ "$verdict" = hook_failed ]; then
				reason="$(error_reason "$BRANCH_OUTPUT")"
			else
				reason="$(error_reason "$output")"
			fi
			log_fire "$id" error "${streak:+$streak: }${reason:-no output}" "$title"
			error_task "$id" "$title" "$err_label: ${reason:-no output}"
			if [ "$(record_to "$record")" = gordon ] && notify_gordon "$id" "error: $title" "$err_label${streak:+, $streak} $output"; then
				log_fire "$id" delivered "gordon error" "$title"
			fi
			if [ "$notify" = mail ]; then
				printf '%s\n%s\n' "$err_label${streak:+, $streak}" "$output" | "$MAILER" "error: $title"
				log_fire "$id" mailed error "$title"
			fi
			# A one-shot that errored runs again after the default snooze; a
			# repeat retries on its own schedule.
			if [ -z "$(jq -r '.repeat // ""' <<<"$record")" ]; then
				update_record "$id" '.when = $retry' --arg retry "$(parse_when "$DEFAULT_SNOOZE")"
				cmd_sync >/dev/null
			fi
			;;
		esac
		;;
	esac
}

# The deadline clock: the packet's check neither succeeded nor failed in
# time. This is the one reminder on a clock, so it reaches Piotr whoever owns
# the packet: Gordon gets a line, Piotr the form (extend, send to AI, delete).
# The packet keeps running whatever the answer. The retry is set before the
# form opens, so a dismissed or dying form comes back after the default snooze.
cmd_deadline() {
	local id="$1" record status title deadline subject url late_s
	valid_id "$id" || die "Invalid id $id."
	export DISPLAY="${DISPLAY:-:0}"
	export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"
	record="$(get_record "$id")" || {
		log_fire "$id" missing "deadline" ""
		return 0
	}
	status="$(jq -r '.status' <<<"$record")"
	title="$(record_title "$record")"
	deadline="$(jq -r '.deadline // ""' <<<"$record")"
	if [ "$status" != active ] || [ -z "$(deadline_due "$record")" ]; then
		log_fire "$id" skipped "deadline: status $status${deadline:+, deadline $deadline}" "$title"
		return 0
	fi
	late_s=$(($(date +%s) - $(epoch_of "$deadline")))
	if [ "$late_s" -lt 0 ]; then
		log_fire "$id" skipped "deadline moved to $deadline" "$title"
		return 0
	fi
	if [ -z "$(jq -r '.deadline_retry // ""' <<<"$record")" ]; then
		log_fire "$id" deadline "passed $deadline" "$title"
		notify_gordon "$id" "deadline passed: $title" "$(deadline_report "$record")" || true
	else
		log_fire "$id" deadline "still passed $deadline" "$title"
	fi
	update_record "$id" '.deadline_retry = $retry' --arg retry "$(parse_when "$DEFAULT_SNOOZE")"
	cmd_sync >/dev/null
	mkdir -p "$STATE_DIR"
	exec 8>"$STATE_DIR/fire-$id.lock"
	if ! flock -n 8; then
		log_fire "$id" skipped "deadline form already open" "$title"
		return 0
	fi
	record="$(get_record "$id")"
	subject="$(jq -r '.subject // ""' <<<"$record")"
	url="$(subject_url "$subject")" || url=""
	show_dialog "$id" "$record" "$title" "$(deadline_report "$record")" "$url" "$(human_when "$deadline")" \
		"$( [ "$late_s" -gt "$LATE_AFTER" ] && human_duration "$late_s")" deadline
	flock -u 8
}

# What the deadline form and Gordon's line show: what the packet waits for,
# since when, how its checks went, and the last run's output.
deadline_report() {
	local record="$1" id runs last last_out created
	id="$(jq -r '.id' <<<"$record")"
	created="$(jq -r '.created // ""' <<<"$record")"
	runs=0 last=""
	if [ -f "$FIRE_LOG" ]; then
		runs="$(fire_history | awk -F '\t' -v id="$id" '$2 == id && $3 == "exec"' | wc -l)"
		last="$(fire_history | awk -F '\t' -v id="$id" '$2 == id && $3 == "exec" { at = $1; v = $4 } END { if (at != "") print at " " v }')"
	fi
	last_out=""
	[ -f "$RUNS_DIR/$id.log" ] && last_out="$(awk '/^=== / { n = 0; split("", out); next } n == 0 && /^\$ / { next } { out[n++] = $0 } END { for (i = 0; i < n; i++) print out[i] }' "$RUNS_DIR/$id.log" | tail -n 8)"
	printf 'The deadline %s passed and neither the success nor the failure condition held.\n' "$(human_when "$(jq -r '.deadline' <<<"$record")")"
	printf 'Waiting since %s (%s), %s.\n' "${created:+$(human_when "$created")}" "$(jq -r '.origin // "?"' <<<"$record")" "$(record_trigger "$record")"
	printf 'Checks: %s run(s)%s.\n' "$runs" "${last:+, last $last}"
	[ -n "$(jq -r '.command // ""' <<<"$record")" ] && printf 'Runs: %s\n' "$(jq -r '.command' <<<"$record")"
	[ -n "$last_out" ] && printf 'Last output:\n%s\n' "$last_out"
	[ -f "$RUNS_DIR/$id.log" ] && printf 'Run log: %s\n' "$(home_path "$RUNS_DIR/$id.log")"
	return 0
}

# -------------------------------------------------------------- dialogs ----

show_error() {
	jq -nc --arg message "$1" '{message:$message}' | "$GUI" error >/dev/null 2>&1 || true
}

# ------------------------------------------------------ notify triggers ----

# The popup reaches the command as stdin and $REMINDER_MATCH, never as text in
# the command line, so a summary like `$(rm -rf ~)` is inert. Exit 0 is the
# whole verdict: success is silent, anything else reaches Gordon (the record's
# --to), mail (--notify mail), or an error dialog. The record stays active.
fire_on_notify() {
	local id="$1" record="$2" title="$3" token="$4" match="" command rc=0 output notify
	if [ -n "$token" ]; then
		[[ "$token" =~ ^[0-9a-f]{16}$ ]] || die "Invalid match token $token."
		if ! match="$(cat "$MATCH_DIR/$token" 2>/dev/null)"; then
			log_fire "$id" missing "match $token" "$title"
			return 0
		fi
		rm -f "$MATCH_DIR/$token"
	else
		match="${REMINDER_MATCH:-}"
	fi
	log_fire "$id" fired "exec on popup${token:+ (delayed)}" "$title"
	update_record "$id" '.last_fired = $now' --arg now "$(now_iso)"
	command="$(jq -r '.command // ""' <<<"$record")"
	output="$(printf '%s\n' "$match" | REMINDER_MATCH="$match" timeout "$NOTIFY_TIMEOUT" bash -c "$command" 2>&1)" || rc=$?
	log_fire "$id" exec "rc=$rc" "$title"
	log_run "$id" "$rc" "$command" "$output" "" "" 0 ""
	[ "$rc" -eq 0 ] && return 0
	local streak reason err_label
	streak="$(error_streak "$id")"
	reason="$(error_reason "$output")"
	err_label="exit $rc"
	[ "$rc" -eq 124 ] && err_label="timed out after ${NOTIFY_TIMEOUT}s"
	err_label="$err_label${streak:+, $streak}"
	log_fire "$id" error "${streak:+$streak: }${reason:-no output}" "$title"
	notify="$(jq -r '.notify // ""' <<<"$record")"
	if [ "$(record_to "$record")" = gordon ] && notify_gordon "$id" "error: $title" "$err_label $output"; then
		log_fire "$id" delivered "gordon error" "$title"
	elif [ "$notify" != mail ]; then
		show_error "error: $title"$'\n'"$err_label"$'\n'"$output"
	fi
	if [ "$notify" = mail ]; then
		printf '%s\n%s\n' "$err_label" "$output" | "$MAILER" "error: $title"
		log_fire "$id" mailed error "$title"
	fi
}

# A delayed fire: the popup goes to a match file, the at job body carries the
# reminder id and the file's token only. Queue n is never rebuilt by sync, so
# the job survives every add, edit and done.
queue_delayed_fire() {
	local id="$1" line="$2" delay="$3" title="$4" token minutes output status=0
	mkdir -p "$MATCH_DIR"
	token="$(new_id)$(new_id)"
	printf '%s\n' "$line" >"$MATCH_DIR/$token"
	minutes=$(($(delay_seconds "$delay") / 60))
	[ "$minutes" -ge 1 ] || minutes=1
	output="$(printf '%q fire %s %s\n' "$SELF" "$id" "$token" | at -q "$NOTIFY_AT_QUEUE" "now + $minutes minutes" 2>&1)" || status=$?
	if [ "$status" -ne 0 ]; then
		rm -f "$MATCH_DIR/$token"
		log_fire "$id" error "at rejected the delayed fire: $(error_reason "$output")" "$title"
		notify_gordon "$id" "error: $title" "at rejected the delayed fire: $output" || true
		return 1
	fi
	log_fire "$id" queued "fire in $delay ($token)" "$title"
}

# One line of the notification log against the pass's on-notify records:
# fires, queues, or skips each one it matches. Stale (older than
# NOTIFY_WINDOW, the watcher was down) and seen (the cursor was reset) popups
# never fire and are only logged: the mod stops hiding popups while the
# heartbeat is stale, so Gordon already saw what a down watcher missed.
match_line() {
	local line="$1" now="$2" rules="$3" ts app age key id delay title matches
	[[ "$line" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2})$'\t'([^$'\t']*)$'\t' ]] || return 0
	ts="${BASH_REMATCH[1]}" app="${BASH_REMATCH[2]}"
	[ "$app" != reminder ] || return 0
	matches="$(jq -c --arg line "$line" '.on_notify as $re | select(try ($line | test($re)) catch false)' <<<"$rules")"
	[ -n "$matches" ] || return 0
	age=$((now - $(epoch_of "$ts")))
	key="$(printf '%s' "$line" | sha1sum | cut -c1-40)"
	while IFS= read -r record; do
		[ -n "$record" ] || continue
		id="$(jq -r '.id' <<<"$record")"
		title="$(record_title "$record")"
		if [ "$age" -gt "$NOTIFY_WINDOW" ]; then
			log_fire "$id" stale "popup $(human_duration "$age") old" "$title"
			continue
		fi
		if grep -qF $'\t'"$id:$key" "$NOTIFY_SEEN" 2>/dev/null; then
			log_fire "$id" skipped "already fired for this popup" "$title"
			continue
		fi
		printf '%s\t%s:%s\n' "$now" "$id" "$key" >>"$NOTIFY_SEEN"
		delay="$(jq -r '.delay // ""' <<<"$record")"
		if [ -n "$delay" ]; then
			queue_delayed_fire "$id" "$line" "$delay" "$title" || true
		else
			REMINDER_MATCH="$line" "$SELF" fire "$id" </dev/null || true
		fi
	done <<<"$matches"
}

# One pass: the complete lines past the cursor. The cursor moves before any
# fire, so a crash mid-command cannot replay the popup; notify.seen covers a
# cursor reset (the logger trims the file in place, which shrinks it).
cmd_match() {
	own_clocks || die "match: $STORE is not the default store, so it may not fire reminders or queue at jobs."
	mkdir -p "$STATE_DIR"
	local now size cursor=0 chunk total partial complete
	now="$(date +%s)"
	touch "$NOTIFY_ALIVE"
	if [ -f "$NOTIFY_SEEN" ]; then
		awk -F '\t' -v cutoff="$((now - NOTIFY_WINDOW))" '$1 >= cutoff' "$NOTIFY_SEEN" >"$NOTIFY_SEEN.tmp" && mv "$NOTIFY_SEEN.tmp" "$NOTIFY_SEEN"
	fi
	[ -f "$NOTIFY_LOG" ] || return 0
	size="$(stat -c %s "$NOTIFY_LOG")"
	if [ ! -f "$NOTIFY_CURSOR" ]; then
		# No cursor yet: start at the end, so a first run does not walk history.
		printf '%s' "$size" >"$NOTIFY_CURSOR"
		return 0
	fi
	cursor="$(cat "$NOTIFY_CURSOR")"
	[[ "$cursor" =~ ^[0-9]+$ ]] || cursor=0
	# The byte before the cursor must be a newline: command substitution
	# strips one, so a non-empty result is a cursor inside a rewritten line.
	if [ "$cursor" -gt "$size" ] || { [ "$cursor" -gt 0 ] && [ -n "$(tail -c +"$cursor" "$NOTIFY_LOG" | head -c1)" ]; }; then
		cursor=0
	fi
	[ "$cursor" -lt "$size" ] || return 0
	chunk="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/remind-match.XXXXXX")"
	tail -c +"$((cursor + 1))" "$NOTIFY_LOG" >"$chunk"
	total="$(wc -c <"$chunk")"
	partial=0
	[ "$(tail -c1 "$chunk")" = "" ] || partial="$(tail -n1 "$chunk" | wc -c)"
	complete=$((total - partial))
	if [ "$complete" -le 0 ]; then
		rm -f "$chunk"
		return 0
	fi
	printf '%s' "$((cursor + complete))" >"$NOTIFY_CURSOR.tmp" && mv "$NOTIFY_CURSOR.tmp" "$NOTIFY_CURSOR"
	# The records are read once per pass, not once per line: a backlog of a
	# few hundred lines against the store per line took minutes.
	local rules
	rules="$(active_records | jq -c 'select(.on_notify)')"
	if [ -n "$rules" ]; then
		while IFS= read -r line; do
			[ -n "$line" ] || continue
			match_line "$line" "$now" "$rules"
		done < <(head -c "$complete" "$chunk")
	fi
	rm -f "$chunk"
}

# The service loop: a pass per change to the log, or every NOTIFY_POLL seconds
# so a missed inotify event costs seconds, not a popup.
cmd_watch() {
	own_clocks || die "watch: $STORE is not the default store."
	trap 'exit 0' TERM INT
	while :; do
		cmd_match || printf 'match pass failed with %s\n' "$?" >&2
		if [ -f "$NOTIFY_LOG" ] && command -v inotifywait >/dev/null 2>&1; then
			inotifywait -qq -e modify -e close_write -e move_self -t "$NOTIFY_POLL" "$NOTIFY_LOG" 2>/dev/null || true
		else
			sleep "$NOTIFY_POLL"
		fi
	done
}

# `watch <thread-url> [--task <uuid>] ...` subscribes to a thread. Bare `watch`
# is the notification daemon, so arguments must never fall through to it: it
# ignores them and loops forever.
cmd_watch_thread() {
	local bin="${THREAD_WATCH_BIN:-$HOME/.claude/scripts/__thread_watch.sh}"
	[ -x "$bin" ] || die "watch: $bin not found or not executable."
	exec "$bin" subscribe "$@" </dev/null
}

cmd_open() {
	local id="$1" url
	valid_id "$id" || die "Invalid id $id."
	url="$(subject_url "$(get_record "$id" | jq -r '.subject // ""')")" || {
		show_error "This reminder carries no link to open."
		return 1
	}
	open_url "$url" || show_error "Could not open $url"
}

cmd_add_dialog() {
	local response label when repeat subject
	response="$(jq -nc '{title:"Add reminder"}' | "$GUI" form)" || return 0
	label="$(jq -r '.label // ""' <<<"$response")"
	when="$(jq -r '.when // ""' <<<"$response")"
	repeat="$(jq -r '.repeat // ""' <<<"$response")"
	subject="$(jq -r '.subject // ""' <<<"$response")"
	local -a args=()
	[ -n "$label" ] && args+=(--label "$label")
	[ -n "$when" ] && args+=(--when "$when")
	[ -n "$repeat" ] && args+=(--repeat "$repeat")
	[ -n "$subject" ] && args+=(--subject "$subject")
	cmd_add "${args[@]}" --origin dialog 2>"$STATE_DIR/.dialog-error" || {
		show_error "$(cat "$STATE_DIR/.dialog-error")"
		return 1
	}
}

cmd_edit_dialog() {
	local id="$1" record label when shown_when repeat subject response
	valid_id "$id" || die "Invalid id $id."
	record="$(get_record "$id")" || die "No reminder with id $id."
	label="$(jq -r '.label // ""' <<<"$record")"
	when="$(jq -r '.when // ""' <<<"$record")"
	repeat="$(jq -r '.repeat // ""' <<<"$record")"
	subject="$(jq -r '.subject // ""' <<<"$record")"
	shown_when="${when:+$(date -d "$when" '+%Y-%m-%d %H:%M')}"
	response="$(jq -nc --arg label "$label" --arg when "$shown_when" --arg repeat "$repeat" --arg subject "$subject" \
		'{title:"Edit reminder", label:$label, when:$when, repeat:$repeat, subject:$subject}' | "$GUI" form)" || return 0
	local -a args=()
	local value
	value="$(jq -r '.label // ""' <<<"$response")"
	[ "$value" != "$label" ] && args+=(--label "$value")
	value="$(jq -r '.when // ""' <<<"$response")"
	[ "$value" != "$shown_when" ] && [ -n "$value" ] && args+=(--when "$value")
	value="$(jq -r '.repeat // ""' <<<"$response")"
	[ "$value" != "$repeat" ] && [ -n "$value" ] && args+=(--repeat "$value")
	value="$(jq -r '.subject // ""' <<<"$response")"
	[ "$value" != "$subject" ] && [ -n "$value" ] && args+=(--subject "$value")
	[ "${#args[@]}" -gt 0 ] || return 0
	cmd_edit "$id" "${args[@]}" 2>"$STATE_DIR/.dialog-error" || {
		show_error "$(cat "$STATE_DIR/.dialog-error")"
		return 1
	}
}

cmd_delete_dialog() {
	local id="$1" title
	valid_id "$id" || die "Invalid id $id."
	title="$(record_title "$(get_record "$id")")"
	jq -nc --arg message "Delete reminder: $title?" \
		'{title:"Delete reminder", message:$message, confirm_label:"Delete"}' \
		| "$GUI" confirm >/dev/null || return 0
	cmd_delete "$id" >/dev/null
}

# ----------------------------------------------------------------- main ----

verb="${1:-}"
[ $# -gt 0 ] && shift
case "$verb" in
add) cmd_add "$@" ;;
list) cmd_list "$@" ;;
edit) [ -n "${1:-}" ] || die "edit needs an id."; cmd_edit "$@" ;;
agenda) cmd_agenda "$@" ;;
done) [ -n "${1:-}" ] || die "done needs an id."; cmd_done "$1" ;;
delete) [ -n "${1:-}" ] || die "delete needs an id."; cmd_delete "$1" ;;
sync) cmd_sync ;;
gc) cmd_gc ;;
compact) cmd_compact ;;
rotate-log) cmd_rotate_log ;;
fire) [ -n "${1:-}" ] || die "fire needs an id."; cmd_fire "$1" "${2:-}" ;;
deadline) [ -n "${1:-}" ] || die "deadline needs an id."; cmd_deadline "$1" ;;
match) cmd_match ;;
watch) if [ $# -gt 0 ]; then cmd_watch_thread "$@"; else cmd_watch; fi ;;
open) [ -n "${1:-}" ] || die "open needs an id."; cmd_open "$1" ;;
add-dialog) cmd_add_dialog ;;
edit-dialog) [ -n "${1:-}" ] || die "edit-dialog needs an id."; cmd_edit_dialog "$1" ;;
delete-dialog) [ -n "${1:-}" ] || die "delete-dialog needs an id."; cmd_delete_dialog "$1" ;;
"") cmd_agenda ;;
-h | --help) usage ;;
*) die "Unknown verb $verb. Try remind --help." ;;
esac
