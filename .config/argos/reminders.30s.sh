#!/usr/bin/env bash
# Argos applet for reminders. A consumer of `remind list --json` only: it never
# touches the store, at, or cron, and every action it offers passes an id.

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

# One record per line: fields are joined with the unit separator (a tab is
# IFS whitespace, so read would collapse an empty repeat and shift the rest),
# and a multi-line subject is cut to its first line before it can split a row.
sep=$'\x1f'
mapfile -t records < <("$helper" list --json 2>/dev/null \
	| jq -r --arg sep "$sep" '.[] | [.id, (.when // ""), (.repeat // ""), (.title | gsub("\n"; " ")), (.url // ""), (.subject // "" | split("\n")[0]), (.overdue // false | tostring)] | join($sep)')
count="${#records[@]}"
overdue_count=0
for record in "${records[@]}"; do
	[[ "$record" == *"${sep}true" ]] && overdue_count=$((overdue_count + 1))
done

if [ "$count" -eq 0 ]; then
	color="#666666"
elif [ "$overdue_count" -gt 0 ]; then
	color="#ff9944"
else
	color="#44ff44"
fi

echo "<tt><b>⏰:</b></tt><tt><span color='${color}'>${count}</span></tt> | font='monospace' size=12"
echo "---"
echo "➕ Add reminder | bash='\"$helper\" add-dialog' terminal=false refresh=true"
echo "---"

if [ "$count" -eq 0 ]; then
	echo "No active reminders | color=#888888"
else
	for record in "${records[@]}"; do
		IFS="$sep" read -r id when repeat title url subject overdue <<<"$record"
		schedule=""
		[ -n "$when" ] && schedule="$(date -d "$when" '+%a %d %b %H:%M' 2>/dev/null || printf '%s' "$when")"
		[ -n "$repeat" ] && schedule="${schedule:+$schedule, }repeats $repeat"
		when_color="#aaaaaa"
		[ "$overdue" = true ] && when_color="#ff9944"
		printf '%s\n' "$(escape_label "$title")"
		echo "--$(escape_label "$schedule") | color=$when_color size=10"
		# One dim line naming the subject. A task shows its short uuid, not
		# its content: the dialog reads the task live when it fires.
		case "$subject" in
		task:*) echo "--task ${subject:5:8} | color=#aaaaaa size=10" ;;
		text:*)
			first_line="${subject#text:}"
			[ -n "$first_line" ] && echo "--$(escape_label "${first_line:0:60}") | color=#aaaaaa size=10"
			;;
		esac
		[ -n "$url" ] \
			&& echo "--🔗 Open link | bash='\"$helper\" open $id' terminal=false refresh=false"
		echo "--Snooze 1h | bash='\"$helper\" edit $id --when 1h' terminal=false refresh=true"
		echo "--Edit | bash='\"$helper\" edit-dialog $id' terminal=false refresh=true"
		echo "--Done | bash='\"$helper\" done $id' terminal=false refresh=true"
		echo "--Delete | bash='\"$helper\" delete-dialog $id' terminal=false refresh=true color=#ff6666"
	done
fi

echo "---"
echo "Sync clocks | bash='\"$helper\" sync' terminal=false refresh=true"
echo "Refresh | refresh=true"
