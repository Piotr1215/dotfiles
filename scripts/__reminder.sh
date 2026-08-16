#!/usr/bin/env bash

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${REMINDER_STATE_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/reminders/reminders.tsv}"
STATE_LOCK="${STATE_FILE}.lock"
GUI="${REMINDER_GUI:-$SCRIPT_DIR/__reminder_gui.py}"

display_help() {
	cat <<'EOF'
Usage: remind <description> <time>/<opt -- time>

Examples:
  remind 'Take a break' 10m
  remind 'Meeting' 2h
  remind 'Submit report' 1d
  remind 'Do laundry' -- 'Monday 13:00'
  remind --list

Supported date and time modifiers:
  m: minutes
  h: hours
  d: days
  w: weeks
  y: years
  --: escape hatch for arbitrary 'at' modifiers
EOF
}

encode_message() {
	printf '%s' "$1" | base64 -w0
}

decode_message() {
	printf '%s' "$1" | base64 -d 2>/dev/null
}

prepare_state() {
	mkdir -p "$(dirname "$STATE_FILE")"
	touch "$STATE_FILE" "$STATE_LOCK"
}

metadata_set() {
	local job_id="$1"
	local encoded="$2"
	local temp

	prepare_state
	exec 9>"$STATE_LOCK"
	flock 9
	temp="$(mktemp "${STATE_FILE}.XXXXXX")"
	awk -F '\t' -v id="$job_id" '$1 != id' "$STATE_FILE" >"$temp"
	printf '%s\t%s\n' "$job_id" "$encoded" >>"$temp"
	mv "$temp" "$STATE_FILE"
	flock -u 9
}

metadata_remove() {
	local job_id="$1"
	local temp

	prepare_state
	exec 9>"$STATE_LOCK"
	flock 9
	temp="$(mktemp "${STATE_FILE}.XXXXXX")"
	awk -F '\t' -v id="$job_id" '$1 != id' "$STATE_FILE" >"$temp"
	mv "$temp" "$STATE_FILE"
	flock -u 9
}

metadata_get() {
	local job_id="$1"
	[ -f "$STATE_FILE" ] || return 1
	awk -F '\t' -v id="$job_id" '$1 == id { print $2; found=1; exit } END { if (!found) exit 1 }' "$STATE_FILE"
}

prune_metadata() {
	local active_ids="$1"
	local temp
	local job_id encoded
	declare -A active=()

	while read -r job_id _; do
		[[ "$job_id" =~ ^[0-9]+$ ]] && active["$job_id"]=1
	done <<<"$active_ids"

	prepare_state
	exec 9>"$STATE_LOCK"
	flock 9
	temp="$(mktemp "${STATE_FILE}.XXXXXX")"
	while IFS=$'\t' read -r job_id encoded; do
		[ -n "${active[$job_id]:-}" ] && printf '%s\t%s\n' "$job_id" "$encoded" >>"$temp"
	done <"$STATE_FILE"
	mv "$temp" "$STATE_FILE"
	flock -u 9
}

list_records() {
	local jobs
	local job_id day month date clock year _queue _owner rest encoded
	declare -A messages=()

	jobs="$(atq 2>/dev/null || true)"
	prune_metadata "$jobs"

	while IFS=$'\t' read -r job_id encoded; do
		[ -n "$job_id" ] && messages["$job_id"]="$encoded"
	done <"$STATE_FILE"

	while read -r job_id day month date clock year _queue _owner rest; do
		[[ "$job_id" =~ ^[0-9]+$ ]] || continue
		printf '%s\t%s %s %s %s %s\t%s\n' \
			"$job_id" "$day" "$month" "$date" "$clock" "$year" "${messages[$job_id]:-}"
	done <<<"$jobs"
}

job_schedule() {
	local wanted="$1"
	local job_id day month date clock year _queue _owner rest

	while read -r job_id day month date clock year _queue _owner rest; do
		if [ "$job_id" = "$wanted" ]; then
			printf '%s %s %s %s %s' "$day" "$month" "$date" "$clock" "$year"
			return 0
		fi
	done < <(atq 2>/dev/null)
	return 1
}

delay_for() {
	local value="$1"

	case "$value" in
	tomorrow) printf '8:00 AM tomorrow' ;;
	eow) printf '12:00 PM next Fri' ;;
	eod) printf '8:00 PM' ;;
	*)
		if [[ "$value" =~ ^([0-9]+)([mhdwy])$ ]]; then
			case "${BASH_REMATCH[2]}" in
			m) printf 'now + %s minutes' "${BASH_REMATCH[1]}" ;;
			h) printf 'now + %s hours' "${BASH_REMATCH[1]}" ;;
			d) printf 'now + %s days' "${BASH_REMATCH[1]}" ;;
			w) printf 'now + %s weeks' "${BASH_REMATCH[1]}" ;;
			y) printf 'now + %s years' "${BASH_REMATCH[1]}" ;;
			esac
		else
			return 1
		fi
		;;
	esac
}

schedule_delay() {
	local message="$1"
	local delay="$2"
	local encoded command_output status job_id script_path
	local display="${DISPLAY:-:0}"
	local -a at_args

	encoded="$(encode_message "$message")"
	script_path="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"

	if [[ "$delay" == exact:* ]]; then
		at_args=(-t "${delay#exact:}")
	else
		at_args=("$delay")
	fi
	command_output="$(printf 'DISPLAY=%q %q --notify %q\n' "$display" "$script_path" "$encoded" | at "${at_args[@]}" 2>&1)"
	status=$?
	if [ "$status" -ne 0 ]; then
		printf '%s\n' "$command_output" >&2
		return "$status"
	fi

	job_id="$(sed -n 's/^job \([0-9][0-9]*\) at.*/\1/p' <<<"$command_output" | tail -n1)"
	if [ -z "$job_id" ]; then
		printf 'Reminder was queued, but its at job ID could not be read.\n' >&2
		return 1
	fi

	metadata_set "$job_id" "$encoded"
	printf 'Scheduled reminder as at job %s.\n' "$job_id"
}

schedule_input() {
	local message="$1"
	local value="$2"
	local delay

	if delay="$(delay_for "$value")"; then
		schedule_delay "$message" "$delay"
	else
		schedule_delay "$message" "$value"
	fi
}

cancel_job() {
	local job_id="$1"
	[[ "$job_id" =~ ^[0-9]+$ ]] || return 2
	atrm "$job_id" || return
	metadata_remove "$job_id"
}

notify() {
	local message="$1"
	local response action delay

	while true; do
		response="$(jq -nc --arg message "$message" '{message:$message}' | "$GUI" alert)" || break
		action="$(jq -r '.action // ""' <<<"$response")"
		case "$action" in
		acknowledge)
			task log "$message" +reminder
			break
			;;
		snooze)
			delay="$(jq -r '.minutes // ""' <<<"$response")"
			if [[ "$delay" =~ ^[0-9]+$ ]]; then
				sleep $((delay * 60))
			else
				break
			fi
			;;
		*) break ;;
		esac
	done
}

show_error() {
	jq -nc --arg message "$1" '{message:$message}' | "$GUI" error >/dev/null 2>&1 || true
}

add_dialog() {
	local response message when

	response="$(jq -nc '{title:"Add reminder"}' | "$GUI" form)" || return 0
	message="$(jq -er '.message | select(length > 0)' <<<"$response")" || return 0
	when="$(jq -er '.when | select(length > 0)' <<<"$response")" || return 0

	schedule_input "$message" "$when" || {
		show_error "Could not schedule the reminder for: $when"
		return 1
	}
}

edit_dialog() {
	local job_id="$1"
	local encoded response message when current_schedule exact_time

	encoded="$(metadata_get "$job_id")" || {
		show_error "This at job has no reminder text to edit."
		return 1
	}
	message="$(decode_message "$encoded")" || return 1
	current_schedule="$(job_schedule "$job_id")" || {
		show_error "At job $job_id is no longer active."
		return 1
	}
	response="$(jq -nc --arg message "$message" --arg when "$current_schedule" \
		'{title:"Edit and reschedule reminder", message:$message, when:$when}' | "$GUI" form)" || return 0
	message="$(jq -er '.message | select(length > 0)' <<<"$response")" || return 0
	when="$(jq -er '.when | select(length > 0)' <<<"$response")" || return 0
	if [ "$when" = "$current_schedule" ]; then
		exact_time="$(date -d "$current_schedule" +%Y%m%d%H%M)" || {
			show_error "Could not preserve the current reminder time."
			return 1
		}
		when="exact:$exact_time"
	fi

	schedule_input "$message" "$when" || {
		show_error "Could not schedule the replacement for: $when"
		return 1
	}
	cancel_job "$job_id"
}

cancel_dialog() {
	local job_id="$1"

	jq -nc --arg message "Cancel at job $job_id?" \
		'{title:"Cancel reminder", message:$message, confirm_label:"Cancel reminder"}' \
		| "$GUI" confirm >/dev/null || return 0
	cancel_job "$job_id" || show_error "Could not cancel at job $job_id."
}

adopt_dialog() {
	local job_id="$1"
	local response message

	[[ "$job_id" =~ ^[0-9]+$ ]] || return 2
	if ! atq 2>/dev/null | awk -v id="$job_id" '$1 == id { found=1 } END { exit !found }'; then
		show_error "At job $job_id is no longer active."
		return 1
	fi
	response="$(jq -nc --arg job "$job_id" '{job:$job}' | "$GUI" name)" || return 0
	message="$(jq -er '.message | select(length > 0)' <<<"$response")" || return 0
	metadata_set "$job_id" "$(encode_message "$message")"
}

if [[ "${3:-}" == "internal" ]]; then
	notify "$1"
	exit
fi

case "${1:-}" in
--notify)
	notify "$(decode_message "${2:-}")"
	;;
-l|--list)
	atq
	;;
--records)
	list_records
	;;
--add-dialog)
	add_dialog
	;;
--edit-dialog)
	edit_dialog "${2:-}"
	;;
--cancel)
	cancel_job "${2:-}"
	;;
--cancel-dialog)
	cancel_dialog "${2:-}"
	;;
--adopt-dialog)
	adopt_dialog "${2:-}"
	;;
-h|--help|"")
	display_help
	;;
*)
	message="$1"
	if [ "${2:-}" = "--" ]; then
		[ -n "${3:-}" ] || { printf 'Missing time after --.\n' >&2; exit 2; }
		schedule_delay "$message" "$3"
	else
		delay="$(delay_for "${2:-}")" || { printf 'Invalid time format.\n' >&2; exit 1; }
		schedule_delay "$message" "$delay"
	fi
	;;
esac
