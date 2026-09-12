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
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$(readlink -f "${BASH_SOURCE[0]}")"
STATE_DIR="${REMINDER_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/reminders}"
STORE="${REMINDER_STORE:-$STATE_DIR/reminders.jsonl}"
FIRE_LOG="${REMINDER_LOG:-$STATE_DIR/fire.log}"
LOCK="${STORE}.lock"
GUI="${REMINDER_GUI:-$SCRIPT_DIR/__reminder_gui.py}"
URL_OPENER="${REMINDER_URL_OPENER:-$SCRIPT_DIR/__taskopen_url_open.sh}"
TASK_OPENER="${REMINDER_TASK_OPENER:-$SCRIPT_DIR/__task_open.sh}"
MAILER="${REMINDER_MAILER:-$SCRIPT_DIR/__mail_me.sh}"
CRON_RUN="${REMINDER_CRON_RUN:-$SCRIPT_DIR/__cron_run.sh}"
CRON_EVERY="${REMINDER_CRON_EVERY:-$SCRIPT_DIR/__cron_every.sh}"
STAMP_DIR="${CRON_EVERY_STAMP_DIR:-$HOME/.local/state/cron-every}"
AT_QUEUE="r"
CRON_BEGIN="# BEGIN remind (managed by __reminder.sh sync, edits here are overwritten)"
CRON_END="# END remind"
DEFAULT_SNOOZE="${REMINDER_DEFAULT_SNOOZE:-15 minutes}"
LATE_AFTER=300

usage() {
	cat <<'USAGE'
Usage: remind [<verb> [args]]   (no verb: the agenda, the whole list in $EDITOR)

  add <label> <when> [options]      one-shot reminder
  add <label> --repeat <spec> [options]
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
  gc                                compact the store to active records
  fire <id>                         what the clocks call; runs the action

Options for add and edit:
  --when <spec>       10m 2h 1d 1w, tomorrow, eod, eow, or anything date -d
                      accepts: 'Tuesday 16:20', '2026-09-10 09:30', 'next monday 9:00'
  --repeat <spec>     5-field cron ('0 9 * * 1') or 'every 7d' (m h d w units)
  --subject <s>       task:<uuid>, url:<url>, or free text (stored as text:)
  --action <a>        show (default), open, exec
  --notify <n>        dialog (default), mail, or silent: how a hit or a show reaches you
  --on-hit <shell>    runs after an exec hit, check output on stdin (chain with &&);
                      if it fails the reminder reports and keeps its schedule
  --on-miss <shell>   runs after an exec miss (exit 0), same
  --command <cmd>     literal command for the exec action; its exit code is the
                      verdict: 0 silent, 2 hit (shows output, retires the reminder,
                      a repeat too), else error (shows output, keeps the schedule)
  --origin <o>        who created it (cli, claude, dialog, migrate)

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
update_record() {
	local id="$1" filter="$2" record updated
	shift 2
	record="$(get_record "$id")" || die "No reminder with id $id."
	updated="$(jq -c "$@" "$filter | with_entries(select(.value != null and .value != \"\"))" <<<"$record")"
	append_record "$updated"
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

human_when() {
	date -d "$1" '+%a %d %b %H:%M'
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

# Every queue-r job, one line each: job_id <TAB> epoch <TAB> reminder id.
# The id is the last word of the job body; the environment dump above it is
# never parsed.
at_jobs() {
	local job_id day month date clock year _queue _owner rid
	while read -r job_id day month date clock year _queue _owner; do
		[[ "$job_id" =~ ^[0-9]+$ ]] || continue
		rid="$(at -c "$job_id" 2>/dev/null | grep -o 'fire [0-9a-f]\{8\}[[:space:]]*$' | tail -n1 | awk '{print $2}')" || true
		printf '%s\t%s\t%s\n' "$job_id" "$(epoch_of "$day $month $date $clock $year")" "${rid:-}"
	done < <(atq -q "$AT_QUEUE" 2>/dev/null || true)
}

at_schedule() {
	local id="$1" when="$2" output status=0
	output="$(printf '%q fire %s\n' "$SELF" "$id" | at -q "$AT_QUEUE" -t "$(at_time "$when")" 2>&1)" || status=$?
	if [ "$status" -ne 0 ]; then
		printf 'at rejected %s for %s:\n%s\n' "$when" "$id" "$output" >&2
		return "$status"
	fi
}

sync_at() {
	local -A desired=() present=()
	local id when job_id epoch rid record created=0 removed=0 failed=0

	while IFS= read -r record; do
		id="$(jq -r '.id' <<<"$record")"
		when="$(jq -r '.when // ""' <<<"$record")"
		[ -n "$when" ] && desired["$id"]="$(epoch_of "$when")"
	done < <(active_records)

	while IFS=$'\t' read -r job_id epoch rid; do
		if [ -n "$rid" ] && [ "${desired[$rid]:-}" = "$epoch" ] && [ -z "${present[$rid]:-}" ]; then
			present["$rid"]=1
		else
			atrm "$job_id" && removed=$((removed + 1))
		fi
	done < <(at_jobs)

	for id in "${!desired[@]}"; do
		[ -n "${present[$id]:-}" ] && continue
		when="$(get_record "$id" | jq -r '.when')"
		if at_schedule "$id" "$when"; then
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
	printf '@reboot sleep 90 && %s sync\n' "$SELF"
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

cmd_sync() {
	sync_at
	sync_cron
	sync_stamps
}

# ------------------------------------------------------------------ log ----

log_fire() {
	local id="$1" event="$2" detail="$3" label="$4"
	mkdir -p "$(dirname "$FIRE_LOG")"
	printf '%s\t%s\t%s\t%s\t%s\n' "$(now_iso)" "$id" "$event" "$detail" "$(printf '%s' "$label" | tr '\t\n' '  ')" >>"$FIRE_LOG"
}

# ---------------------------------------------------------------- verbs ----

parse_options() {
	# Fills opt_* variables and positional[] from "$@".
	opt_when="" opt_repeat="" opt_subject="" opt_action="" opt_command="" opt_origin="" opt_label="" opt_notify="" opt_on_hit="" opt_on_miss=""
	positional=()
	while [ $# -gt 0 ]; do
		case "$1" in
		--when) opt_when="${2:-}"; shift 2 ;;
		--repeat) opt_repeat="${2:-}"; shift 2 ;;
		--subject) opt_subject="${2:-}"; shift 2 ;;
		--action) opt_action="${2:-}"; shift 2 ;;
		--command) opt_command="${2:-}"; shift 2 ;;
		--notify) opt_notify="${2:-}"; shift 2 ;;
		--on-hit) opt_on_hit="${2:-}"; shift 2 ;;
		--on-miss) opt_on_miss="${2:-}"; shift 2 ;;
		--origin) opt_origin="${2:-}"; shift 2 ;;
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

validate_action() {
	case "$1" in
	show | open) ;;
	exec) [ -n "$2" ] || die "The exec action needs a command." ;;
	*) die "Unknown action $1 (show, open, exec)." ;;
	esac
}

cmd_add() {
	local label when repeat subject action id record
	parse_options "$@"
	label="${opt_label:-${positional[0]:-}}"
	when="${opt_when:-${positional[1]:-}}"
	[ -n "$label" ] || [ -n "$opt_subject" ] || die "A reminder needs a label or a subject."
	[ -n "$when" ] || [ -n "$opt_repeat" ] || die "A reminder needs a time (<when>) or --repeat."
	if [ -n "$when" ]; then
		when="$(parse_when "$when")" || die "Cannot parse time: $when"
	fi
	repeat=""
	if [ -n "$opt_repeat" ]; then
		repeat="$(parse_repeat "$opt_repeat")" || die "Cannot parse repeat: $opt_repeat"
	fi
	subject="$(normalize_subject "$opt_subject")"
	action="${opt_action:-show}"
	validate_action "$action" "$opt_command"
	validate_notify "$opt_notify"
	id="$(new_id)"
	record="$(jq -nc --arg id "$id" --arg label "$label" --arg when "$when" --arg repeat "$repeat" \
		--arg action "$action" --arg subject "$subject" --arg command "$opt_command" \
		--arg notify "$opt_notify" --arg on_hit "$opt_on_hit" --arg on_miss "$opt_on_miss" \
		--arg created "$(now_iso)" --arg origin "${opt_origin:-cli}" \
		'{id:$id, label:$label, when:$when, repeat:$repeat, action:$action, subject:$subject,
		  command:$command, notify:$notify, on_hit:$on_hit, on_miss:$on_miss,
		  created:$created, origin:$origin, status:"active"}
		 | with_entries(select(.value != ""))')"
	append_record "$record"
	check_off_window "$when" "$repeat"
	cmd_sync >/dev/null
	if [ -n "$when" ]; then
		printf 'Added %s: %s at %s\n' "$id" "$(record_title "$record")" "$(human_when "$when")"
	else
		printf 'Added %s: %s, repeat %s\n' "$id" "$(record_title "$record")" "$repeat"
	fi
}

# Turn a record into the editable form: one `field: value` line per field,
# comments on top, the way the secret picker edits an entry. `when` is shown
# the way `add` accepts it, not as the stored ISO string.
edit_form_write() {
	local record="$1" form="$2" id when
	id="$(jq -r '.id' <<<"$record")"
	when="$(jq -r '.when // ""' <<<"$record")"
	[ -n "$when" ] && when="$(date -d "$when" '+%Y-%m-%d %H:%M')"
	{
		printf '# %s  [%s]. Edit, save, quit.\n' "$(record_title "$record")" "$id"
		printf '# when     10m 2h 1d 1w, tomorrow, eod, eow, or anything date -d takes\n'
		printf '# repeat   5-field cron or "every 7d"; empty makes it a one-shot\n'
		printf '# subject  task:<uuid>, url:<url>, or free text\n'
		printf '# action   show, open, exec\n'
		printf '# command  what exec runs; empty clears it\n'
		printf '# notify   dialog, mail, or silent\n'
		printf '# on-hit   shell run after a hit (exit 2), check output on stdin; a failing hook keeps the schedule\n'
		printf '# on-miss  shell run after a miss (exit 0), same\n'
		printf 'label: %s\n' "$(jq -r '.label // ""' <<<"$record")"
		printf 'when: %s\n' "$when"
		printf 'repeat: %s\n' "$(jq -r '.repeat // ""' <<<"$record")"
		printf 'subject: %s\n' "$(jq -r '.subject // ""' <<<"$record")"
		printf 'action: %s\n' "$(jq -r '.action // "show"' <<<"$record")"
		printf 'command: %s\n' "$(jq -r '.command // ""' <<<"$record")"
		printf 'notify: %s\n' "$(jq -r '.notify // "dialog"' <<<"$record")"
		printf 'on-hit: %s\n' "$(jq -r '.on_hit // ""' <<<"$record")"
		printf 'on-miss: %s\n' "$(jq -r '.on_miss // ""' <<<"$record")"
	} >"$form"
}

# Read one field back from the saved form, trimmed. A missing line reads as
# empty, which the caller treats as "clear it".
edit_form_field() {
	sed -n "s/^$2:[[:space:]]*//p" "$1" | head -1 | sed 's/[[:space:]]*$//'
}

# Apply raw field values (as typed in a form or an agenda line) to a record.
# Only fields that differ from the record are written, so an untouched line
# changes nothing and an emptied field clears the stored value. Prints
# Updated or Unchanged; the caller syncs the clocks.
edit_apply() {
	local id="$1" label="$2" when="$3" repeat="$4" subject="$5" action="$6" command="$7" notify="${8:-}" on_hit="${9:-}" on_miss="${10:-}"
	local record filter='.' cur_when cur_subject
	record="$(get_record "$id")"
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
	[ "$on_hit" != "$(jq -r '.on_hit // ""' <<<"$record")" ] && filter="$filter | .on_hit = \$on_hit"
	[ "$on_miss" != "$(jq -r '.on_miss // ""' <<<"$record")" ] && filter="$filter | .on_miss = \$on_miss"
	if [ "$filter" = '.' ]; then
		printf 'Unchanged %s\n' "$id"
		return 0
	fi
	update_record "$id" "$filter" --arg when "$when" --arg repeat "$repeat" --arg subject "$subject" \
		--arg label "$label" --arg action "$action" --arg command "$command" --arg notify "$notify" \
		--arg on_hit "$on_hit" --arg on_miss "$on_miss"
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
		"$(edit_form_field "$form" notify)" "$(edit_form_field "$form" on-hit)" "$(edit_form_field "$form" on-miss)"
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
	local when="$1" repeat="$2" day today
	if [ -z "$when" ]; then
		[ -n "$repeat" ] && printf 'Recurring' || printf 'Unscheduled'
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

agenda_line() {
	local record="$1" id when repeat action command subject stamps notify on_hit on_miss
	id="$(jq -r '.id' <<<"$record")"
	when="$(jq -r '.when // ""' <<<"$record")"
	repeat="$(jq -r '.repeat // ""' <<<"$record")"
	action="$(jq -r '.action // "show"' <<<"$record")"
	command="$(jq -r '.command // ""' <<<"$record")"
	subject="$(jq -r '(.subject // "") | split("\n") | .[0] // ""' <<<"$record")"
	stamps=""
	[ -n "$when" ] && stamps="<$(agenda_stamp "$when")>"
	[ -n "$repeat" ] && stamps="${stamps:+$stamps }<$repeat>"
	printf '** %s %s\n' "$stamps" "$(record_title "$record")"
	[ "$action" != show ] && printf '   :action: %s\n' "$action"
	[ "$action" = exec ] && printf '   :runs: %s\n' "$command"
	notify="$(jq -r '.notify // ""' <<<"$record")"
	[ -n "$notify" ] && printf '   :notify: %s\n' "$notify"
	on_hit="$(jq -r '.on_hit // ""' <<<"$record")"
	[ -n "$on_hit" ] && printf '   :on-hit: %s\n' "$on_hit"
	on_miss="$(jq -r '.on_miss // ""' <<<"$record")"
	[ -n "$on_miss" ] && printf '   :on-miss: %s\n' "$on_miss"
	case "$subject" in
	task:*) printf '   :task: %s\n' "${subject#task:}" ;;
	url:*) printf '   :url: %s\n' "${subject#url:}" ;;
	text:*) printf '   :notes: %s\n' "${subject#text:}" ;;
	esac
	printf '   :id: %s\n\n' "$id"
	return 0
}

agenda_render() {
	local section record when repeat
	local -a sections=(Overdue Today Tomorrow 'This week' Later Recurring Unscheduled)
	local -A bucket=()
	while IFS= read -r record; do
		[ -n "$record" ] || continue
		when="$(jq -r '.when // ""' <<<"$record")"
		repeat="$(jq -r '.repeat // ""' <<<"$record")"
		section="$(agenda_section "$when" "$repeat")"
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
#      :action: open | exec              omitted means show a dialog
#      :runs: command                    for exec; exit 2 is a hit: stops the repeat, then
#      :notify: mail | silent            the hit goes to a dialog (default), your mail, or
#                                        nowhere because the command already told you
#      :on-hit: shell                    runs after a hit, check output on stdin; chain with &&;
#                                        if it fails the hit is reported and the reminder stays for a retry
#      :on-miss: shell                   runs after a miss (exit 0), e.g. __mail_me.sh "not yet"
#      :task: <uuid>                     what it points at: a task (ctrl+5 opens it),
#      :url: <link>                      a link, or
#      :notes: free text                 notes; one of the three per reminder
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
		edit_apply "$cur_id" "$cur_title" "$cur_when" "$cur_repeat" "$cur_subject" "$cur_action" "$cur_command" "$cur_notify" "$cur_on_hit" "$cur_on_miss"
	else
		local -a args=()
		[ -n "$cur_when" ] && args+=(--when "$cur_when")
		[ -n "$cur_repeat" ] && args+=(--repeat "$cur_repeat")
		[ -n "$cur_subject" ] && args+=(--subject "$cur_subject")
		[ -n "$cur_action" ] && args+=(--action "$cur_action")
		[ -n "$cur_command" ] && args+=(--command "$cur_command")
		[ -n "$cur_notify" ] && args+=(--notify "$cur_notify")
		[ -n "$cur_on_hit" ] && args+=(--on-hit "$cur_on_hit")
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
	local cur_open="" cur_id="" cur_title="" cur_when="" cur_repeat="" cur_subject="" cur_action="" cur_command="" cur_notify="" cur_on_hit="" cur_on_miss=""
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
			action | runs | notify | on-hit | on-miss | task | url | notes | subject) ;;
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
			cur_open=1 cur_id="" cur_subject="" cur_command="" cur_action="" cur_notify="" cur_on_hit="" cur_on_miss=""
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
			on-hit) cur_on_hit="$prop_value" ;;
			on-miss) cur_on_miss="$prop_value" ;;
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
	[ -n "$opt_on_hit" ] && filter="$filter | .on_hit = \$on_hit"
	[ -n "$opt_on_miss" ] && filter="$filter | .on_miss = \$on_miss"
	update_record "$id" "$filter" --arg repeat "$repeat" --arg subject "$subject" \
		--arg label "$opt_label" --arg action "$opt_action" --arg command "$opt_command" --arg notify "$opt_notify" \
		--arg on_hit "$opt_on_hit" --arg on_miss "$opt_on_miss"
	cmd_sync >/dev/null
	printf 'Updated %s\n' "$id"
}

# A one-shot is spent; a repeat drops its pending one-shot (a snooze) only.
mark_done() {
	local id="$1"
	if [ -n "$(get_record "$id" | jq -r '.repeat // ""')" ]; then
		update_record "$id" 'del(.when)'
	else
		update_record "$id" '.status = "done" | del(.when)'
	fi
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
	local record id when repeat action title
	while IFS= read -r record; do
		[ -n "$record" ] || continue
		id="$(jq -r '.id' <<<"$record")"
		when="$(jq -r '.when // ""' <<<"$record")"
		repeat="$(jq -r '.repeat // ""' <<<"$record")"
		action="$(jq -r '.action' <<<"$record")"
		title="$(record_title "$record")"
		printf '%s  %-16s  %-14s  %-5s  %s\n' "$id" "${when:+$(human_when "$when")}" "$repeat" "$action" "$title"
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

cmd_gc() {
	local kept
	prepare_store
	lock_store
	kept="$(jq -c -s 'reduce .[] as $r ({}; .[$r.id] = $r) | .[] | select(.status == "active")' "$STORE")"
	printf '%s\n' "$kept" | sed '/^$/d' >"$STORE.tmp"
	mv "$STORE.tmp" "$STORE"
	unlock_store
	printf 'Compacted to %s active records.\n' "$(sed -n '$=' "$STORE" || echo 0)"
}

# ----------------------------------------------------------------- fire ----

show_dialog() {
	local id="$1" record="$2" title="$3" body="$4" url="$5" due="$6" late="$7"
	local subject repeat response action when
	subject="$(jq -r '.subject // ""' <<<"$record")"
	repeat="$(jq -r '.repeat // ""' <<<"$record")"

	while true; do
		response="$(jq -nc --arg title "$title" --arg body "$body" --arg url "$url" \
			--arg due "$due" --arg late "$late" --arg type "$(subject_type "$subject")" --arg repeat "$repeat" \
			'{title:$title, body:$body, url:$url, due:$due, late:$late, subject_type:$type, repeat:$repeat}' \
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
			case "$subject" in
			task:*) task rc.verbose=nothing "${subject#task:}" "done" >/dev/null 2>&1 || true ;;
			esac
			mark_done "$id"
			cmd_sync >/dev/null
			log_fire "$id" "done" "$action" "$title"
			return 0
			;;
		snooze)
			when="$(jq -r '.when // ""' <<<"$response")"
			when="$(parse_when "$when")" || when="$(parse_when "$DEFAULT_SNOOZE")"
			update_record "$id" '.when = $when' --arg when "$when"
			cmd_sync >/dev/null
			log_fire "$id" snoozed "$when" "$title"
			return 0
			;;
		*)
			log_fire "$id" dismissed "snooze $DEFAULT_SNOOZE" "$title"
			return 0
			;;
		esac
	done
}

# Provisional snooze, one-dialog lock, then the dialog decides. The snooze
# comes first so a dialog that dies with the session brings the reminder back
# instead of losing it. The lock keeps one dialog per reminder: the snooze
# re-fires while an unanswered dialog is still on screen (measured: 15 minutes
# away from the desk produced two dialogs), so a fire that finds the lock held
# only refreshed the snooze and leaves the open dialog to decide.
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

# The branch after a check: on_hit after exit 2, on_miss after exit 0, the
# check's output on stdin. Plain shell, so `y.sh && __mail_me.sh "done"`
# chains. A hook's own failure is logged, never fatal: the verdict stands.
run_branch() {
	local id="$1" record="$2" rc="$3" output="$4" title="$5" hook field hrc=0
	case "$rc" in
	2) field=on_hit ;;
	0) field=on_miss ;;
	*) return 0 ;;
	esac
	hook="$(jq -r ".$field // \"\"" <<<"$record")"
	[ -n "$hook" ] || return 0
	BRANCH_OUTPUT="$(printf '%s\n' "$output" | bash -c "$hook" 2>&1)" || hrc=$?
	BRANCH_RC="$hrc"
	log_fire "$id" "$field" "rc=$hrc" "$title"
}

cmd_fire() {
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

	subject="$(jq -r '.subject // ""' <<<"$record")"
	type="$(subject_type "$subject")"
	if [ "$type" = task ]; then
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
		case "$notify" in
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
		# The exit code is the command's verdict, the same channel __cron_run.sh
		# reads: 0 found nothing and stays silent, 2 is a hit that shows the
		# output and retires the reminder (a repeat included, so a verificator
		# stops once it has tripped), anything else is an error that shows and
		# keeps the schedule so the next run can succeed.
		update_record "$id" '.last_fired = $now' --arg now "$(now_iso)"
		command="$(jq -r '.command // ""' <<<"$record")"
		local rc=0 output
		output="$(bash -c "$command" 2>&1)" || rc=$?
		log_fire "$id" exec "rc=$rc" "$title"
		notify="$(jq -r '.notify // "dialog"' <<<"$record")"
		BRANCH_RC=0 BRANCH_OUTPUT=""
		run_branch "$id" "$record" "$rc" "$output" "$title"
		# A hit whose on-hit hook failed is not done: the condition held but
		# the action did not happen, so report it and keep the schedule for
		# a retry.
		local verdict="$rc" err_label="exit $rc"
		if [ "$rc" -eq 2 ] && [ "$BRANCH_RC" -ne 0 ]; then
			verdict=hook_failed
			err_label="on-hit exit $BRANCH_RC"
			output="$BRANCH_OUTPUT"$'\n---\n'"$output"
		fi
		case "$verdict" in
		0) mark_done "$id"; cmd_sync >/dev/null ;;
		2)
			# A hit ends the schedule. With a dialog, acknowledging it is yours
			# (Done and Snooze both work); by mail or silently there is nothing
			# left to ask, so the reminder is done.
			update_record "$id" 'del(.repeat)'
			case "$notify" in
			mail) printf '%s\n' "$output" | "$MAILER" "$title"; update_record "$id" '.status = "done" | del(.when)'; cmd_sync >/dev/null ;;
			silent) update_record "$id" '.status = "done" | del(.when)'; cmd_sync >/dev/null ;;
			*) guarded_dialog "$id" "$record" "$title" "$output" "$url" "$due" "$late" ;;
			esac
			;;
		*)
			# An error keeps the schedule (a repeat retries on its own). A dialog
			# asks what to do with this run; mail reports it and moves on.
			case "$notify" in
			mail) printf '%s\n%s\n' "$err_label" "$output" | "$MAILER" "error: $title"; mark_done "$id"; cmd_sync >/dev/null ;;
			silent) mark_done "$id"; cmd_sync >/dev/null ;;
			*) guarded_dialog "$id" "$record" "$title" "$err_label"$'\n'"$output" "$url" "$due" "$late" ;;
			esac
			;;
		esac
		;;
	esac
}

# -------------------------------------------------------------- dialogs ----

show_error() {
	jq -nc --arg message "$1" '{message:$message}' | "$GUI" error >/dev/null 2>&1 || true
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
fire) [ -n "${1:-}" ] || die "fire needs an id."; cmd_fire "$1" ;;
open) [ -n "${1:-}" ] || die "open needs an id."; cmd_open "$1" ;;
add-dialog) cmd_add_dialog ;;
edit-dialog) [ -n "${1:-}" ] || die "edit-dialog needs an id."; cmd_edit_dialog "$1" ;;
delete-dialog) [ -n "${1:-}" ] || die "delete-dialog needs an id."; cmd_delete_dialog "$1" ;;
"") cmd_agenda ;;
-h | --help) usage ;;
*) die "Unknown verb $verb. Try remind --help." ;;
esac
