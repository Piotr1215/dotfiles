#!/usr/bin/env bash
# Argos applet for reminders. The panel answers "how many" and "is anything
# overdue"; everything else is the agenda, the whole list as an org file
# opened in the editor. A consumer of `remind list --json` only: it never
# touches the store, at, or cron.

set -o pipefail

if [ -n "${REMINDER_HELPER:-}" ]; then
	helper="$REMINDER_HELPER"
else
	script_dir="$(dirname "$(readlink -f "$0")")"
	helper="$(readlink -f "$script_dir/../../scripts/__reminder.sh")"
fi

if [ ! -x "$helper" ]; then
	echo "<tt><b>⏰:</b></tt><tt><span color='#ff4444'>?</span></tt> | font='monospace' size=12"
	echo "---"
	echo "Reminder helper is unavailable"
	exit 0
fi

mapfile -t records < <("$helper" list --json 2>/dev/null | jq -r '.[] | (.overdue // false | tostring)')
count="${#records[@]}"
overdue_count=0
for record in "${records[@]}"; do
	[ "$record" = true ] && overdue_count=$((overdue_count + 1))
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
[ "$overdue_count" -gt 0 ] && echo "$overdue_count overdue | color=#ff9944"
# A new window in the session of the most recent client, the terminal in front
# of Piotr. Not a popup: a ctrl+5 task hint opens its own popup, and tmux will
# not stack one popup on another, so an agenda popup hid every task it opened.
# The window closes when the editor exits. No -t, for the reason
# __task_open.sh gives: a hint runs outside tmux with no client context.
echo "📋 Open agenda | bash='/usr/local/bin/tmux new-window -n reminders \"$helper\" agenda' terminal=false refresh=true"
echo "➕ Add reminder | bash='\"$helper\" add-dialog' terminal=false refresh=true"
echo "---"
echo "Sync clocks | bash='\"$helper\" sync' terminal=false refresh=true"
echo "Refresh | refresh=true"
