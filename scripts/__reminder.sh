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
CRON_RUN="${REMINDER_CRON_RUN:-$SCRIPT_DIR/__cron_run.sh}"
CRON_EVERY="${REMINDER_CRON_EVERY:-$SCRIPT_DIR/__cron_every.sh}"
AT_QUEUE="r"
CRON_BEGIN="# BEGIN remind (managed by __reminder.sh sync, edits here are overwritten)"
CRON_END="# END remind"
DEFAULT_SNOOZE="${REMINDER_DEFAULT_SNOOZE:-15 minutes}"
LATE_AFTER=300

usage() {
	cat <<'USAGE'
Usage: remind <verb> [args]

  add <label> <when> [options]      one-shot reminder
  add <label> --repeat <spec> [options]
  list [--json] [--all]             active records (or every record with --all)
  edit <id> [options]               change fields, then sync
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
  --command <cmd>     literal command for the exec action
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

cmd_sync() {
	sync_at
	sync_cron
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
	opt_when="" opt_repeat="" opt_subject="" opt_action="" opt_command="" opt_origin="" opt_label=""
	positional=()
	while [ $# -gt 0 ]; do
		case "$1" in
		--when) opt_when="${2:-}"; shift 2 ;;
		--repeat) opt_repeat="${2:-}"; shift 2 ;;
		--subject) opt_subject="${2:-}"; shift 2 ;;
		--action) opt_action="${2:-}"; shift 2 ;;
		--command) opt_command="${2:-}"; shift 2 ;;
		--origin) opt_origin="${2:-}"; shift 2 ;;
		--label) opt_label="${2:-}"; shift 2 ;;
		--) shift; positional+=("$@"); break ;;
		-*) die "Unknown option $1" ;;
		*) positional+=("$1"); shift ;;
		esac
	done
}

validate_action() {
	case "$1" in
	show | open) ;;
	exec) [ -n "$2" ] || die "The exec action needs --command." ;;
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
	id="$(new_id)"
	record="$(jq -nc --arg id "$id" --arg label "$label" --arg when "$when" --arg repeat "$repeat" \
		--arg action "$action" --arg subject "$subject" --arg command "$opt_command" \
		--arg created "$(now_iso)" --arg origin "${opt_origin:-cli}" \
		'{id:$id, label:$label, when:$when, repeat:$repeat, action:$action, subject:$subject,
		  command:$command, created:$created, origin:$origin, status:"active"}
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

cmd_edit() {
	local id="$1" filter='.' when repeat subject
	shift
	valid_id "$id" || die "Invalid id $id."
	get_record "$id" >/dev/null || die "No reminder with id $id."
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
	update_record "$id" "$filter" --arg repeat "$repeat" --arg subject "$subject" \
		--arg label "$opt_label" --arg action "$opt_action" --arg command "$opt_command"
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
			[ -n "$url" ] && { open_url "$url" || true; }
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

cmd_fire() {
	local id="$1" record status action subject type title body url due late command
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
		# Provisional snooze before the dialog: if it dies with the session,
		# the reminder comes back instead of vanishing.
		update_record "$id" '.when = $when | .last_fired = $now' \
			--arg when "$(parse_when "$DEFAULT_SNOOZE")" --arg now "$(now_iso)"
		cmd_sync >/dev/null
		show_dialog "$id" "$record" "$title" "$body" "$url" "${due:+$(human_when "$due")}" "$late"
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
		update_record "$id" '.last_fired = $now' --arg now "$(now_iso)"
		command="$(jq -r '.command // ""' <<<"$record")"
		local rc=0
		bash -c "$command" || rc=$?
		log_fire "$id" exec "rc=$rc" "$title"
		mark_done "$id"
		cmd_sync >/dev/null
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
done) [ -n "${1:-}" ] || die "done needs an id."; cmd_done "$1" ;;
delete) [ -n "${1:-}" ] || die "delete needs an id."; cmd_delete "$1" ;;
sync) cmd_sync ;;
gc) cmd_gc ;;
fire) [ -n "${1:-}" ] || die "fire needs an id."; cmd_fire "$1" ;;
open) [ -n "${1:-}" ] || die "open needs an id."; cmd_open "$1" ;;
add-dialog) cmd_add_dialog ;;
edit-dialog) [ -n "${1:-}" ] || die "edit-dialog needs an id."; cmd_edit_dialog "$1" ;;
delete-dialog) [ -n "${1:-}" ] || die "delete-dialog needs an id."; cmd_delete_dialog "$1" ;;
-h | --help | "") usage ;;
*) die "Unknown verb $verb. Try remind --help." ;;
esac
