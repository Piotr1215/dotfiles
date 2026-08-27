#!/usr/bin/env bash

set -o pipefail

if [ -n "${REMINDER_HELPER:-}" ]; then
	helper="$REMINDER_HELPER"
else
	script_dir="$(dirname "$(readlink -f "$0")")"
	helper="$(readlink -f "$script_dir/../../scripts/__reminder.sh")"
fi

escape_label() {
	printf '%s' "$1" | sed \
		-e 's/&/\&amp;/g' \
		-e 's/</\&lt;/g' \
		-e 's/>/\&gt;/g' \
		-e 's/|/¦/g'
}

if [ ! -x "$helper" ]; then
	echo "<tt><b>⏰:</b></tt><tt><span color='#ff4444'>?</span></tt> | font='monospace' size=12"
	echo "---"
	echo "Reminder helper is unavailable"
	exit 0
fi

mapfile -t records < <("$helper" --records)
count="${#records[@]}"

if [ "$count" -eq 0 ]; then
	color="#666666"
else
	color="#44ff44"
fi

echo "<tt><b>⏰:</b></tt><tt><span color='${color}'>${count}</span></tt> | font='monospace' size=12"
echo "---"
echo "➕ Add reminder | bash='\"$helper\" --add-dialog' terminal=false refresh=true"
echo "---"

if [ "$count" -eq 0 ]; then
	echo "No active reminders | color=#888888"
else
	for record in "${records[@]}"; do
		IFS=$'\t' read -r job_id schedule encoded encoded_notes <<<"$record"
		safe_schedule="$(escape_label "$schedule")"
		if [ -n "$encoded" ]; then
			message="$(printf '%s' "$encoded" | base64 -d 2>/dev/null || printf 'Unreadable reminder')"
			safe_message="$(escape_label "$message")"
			echo "${safe_message}"
			echo "--${safe_schedule} | color=#aaaaaa size=10"
			if [ -n "$encoded_notes" ]; then
				notes="$(printf '%s' "$encoded_notes" | base64 -d 2>/dev/null || printf '')"
				# One dim line of context under the schedule. The full text
				# lives in the edit form; this is only a reminder that it exists.
				first_line="$(printf '%s' "$notes" | head -n1)"
				[ -n "$first_line" ] \
					&& echo "--$(escape_label "${first_line:0:60}") | color=#aaaaaa size=10"
				# Pass the job id, never the url: the helper resolves it from
				# tracked state, so nothing from the notes reaches this command line.
				printf '%s' "$notes" | grep -q 'https\?://' \
					&& echo "--🔗 Open link | bash='\"$helper\" --open-link $job_id' terminal=false refresh=false"
			fi
			echo "--Edit or reschedule | bash='\"$helper\" --edit-dialog $job_id' terminal=false refresh=true"
		else
			echo "Untracked at job ${job_id}"
			echo "--${safe_schedule} | color=#aaaaaa size=10"
			echo "--Add reminder text | bash='\"$helper\" --adopt-dialog $job_id' terminal=false refresh=true"
		fi
		echo "--Cancel | bash='\"$helper\" --cancel-dialog $job_id' terminal=false refresh=true color=#ff6666"
	done
fi

echo "---"
echo "Refresh | refresh=true"
