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
SUCCESS_STAMP="${BACKUP_SUCCESS_STAMP:-$HOME/.local/state/backup-last-success}"
MAX_AGE_HOURS="${MAX_AGE_HOURS:-25}"

host=$(hostname)
now=$(date +%s)

# Best-effort alert via email + desktop. Never fails the script.
alert() {
	local summary="$1"
	printf 'Subject: [backup] WATCHDOG: %s\nFrom: %s\nTo: %s\n\n%s\n' \
		"$summary" "$NOTIFY_EMAIL" "$NOTIFY_EMAIL" "$summary" |
		msmtp "$NOTIFY_EMAIL" 2>/dev/null || true
	# notify-send, NOT dunstify: GNOME Shell holds org.freedesktop.Notifications
	# exclusively, so dunst cannot start here (it exits with "Name is acquired by
	# 'gnome-shell'") and every dunstify call was a silent no-op behind `|| true`.
	# This alert path had never once fired. notify-send reaches GNOME and is
	# captured durably by notification-logger.service.
	notify-send --urgency=critical --icon=dialog-warning \
		"Backup watchdog on $host" "$summary" 2>/dev/null || true
}

# Terminal status is the cron wrapper's state channel: 0 no-hit, 2 hit,
# anything else error. An alert is a hit and must say so on stdout too: the
# alert paths used to exit 0 silently, so the wrapper recorded no-hit with
# "(no output)" on 09-13 and 09-14 while the stamp was 62h old (#181).
stale() {
	alert "$1"
	echo "ALERT: $1"
	exit 2
}

if [[ ! -f "$SUCCESS_STAMP" ]]; then
	stale "No successful backup on record (stamp $SUCCESS_STAMP missing). Backup may never have completed since the watchdog was installed."
fi

last=$(cat "$SUCCESS_STAMP" 2>/dev/null || echo 0)
age_hours=$(((now - last) / 3600))

if ((age_hours >= MAX_AGE_HOURS)); then
	stale "Last successful backup was ${age_hours}h ago (threshold ${MAX_AGE_HOURS}h). Nightly backup has not completed cleanly. Check ~/backup.log and whether /mnt/nas-backup is mounted."
fi

echo "OK: last successful backup ${age_hours}h ago"
exit 0
