#!/usr/bin/env bash
set -eo pipefail

# =============================================================================
# Backup dead-man's switch.
#
# __backup.sh writes a unix-timestamp to $SUCCESS_STAMP after every fully clean
# run. This watchdog runs from its own cron entry and alerts if that stamp is
# missing or older than $MAX_AGE_HOURS. It catches the failure class the main
# script CANNOT report on: the backup never running at all (NAS unmounted, cron
# disabled, machine asleep at 20:00), which is exactly what hid the months-long
# gap that motivated this.
# =============================================================================

NOTIFY_EMAIL="piotrzan@gmail.com"
SUCCESS_STAMP="$HOME/.local/state/backup-last-success"
MAX_AGE_HOURS="${MAX_AGE_HOURS:-25}"

host=$(hostname)
now=$(date +%s)

# Best-effort alert via email + desktop. Never fails the script.
alert() {
	local summary="$1"
	printf 'Subject: [backup] WATCHDOG: %s\nFrom: %s\nTo: %s\n\n%s\n' \
		"$summary" "$NOTIFY_EMAIL" "$NOTIFY_EMAIL" "$summary" |
		msmtp "$NOTIFY_EMAIL" 2>/dev/null || true
	dunstify --urgency=critical --icon=dialog-warning \
		"Backup watchdog on $host" "$summary" 2>/dev/null || true
}

if [[ ! -f "$SUCCESS_STAMP" ]]; then
	alert "No successful backup on record (stamp $SUCCESS_STAMP missing). Backup may never have completed since the watchdog was installed."
	exit 0
fi

last=$(cat "$SUCCESS_STAMP" 2>/dev/null || echo 0)
age_hours=$(((now - last) / 3600))

if ((age_hours >= MAX_AGE_HOURS)); then
	alert "Last successful backup was ${age_hours}h ago (threshold ${MAX_AGE_HOURS}h). Nightly backup has not completed cleanly. Check ~/backup.log and whether /mnt/nas-backup is mounted."
else
	# Healthy; stay silent so the watchdog itself never becomes noise.
	echo "OK: last successful backup ${age_hours}h ago"
fi
