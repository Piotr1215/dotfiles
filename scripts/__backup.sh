#!/bin/bash
set -eo pipefail

LOG_FILE="$HOME/backup.log"
LOCK_FILE="/tmp/backup.lock"

# Exit if already running
if [ -f "$LOCK_FILE" ]; then
	echo "Backup already in progress" >>"$LOG_FILE"
	exit 1
fi

# Create lock file
touch "$LOCK_FILE"

# Cleanup on exit
trap 'rm -f $LOCK_FILE' EXIT

{
	date
	rsync -ax --delete \
		--info=progress2 \
		--filter=". $HOME/.backup_patterns" \
		--stats \
		"$HOME/" \
		/mnt/nas-backup/home/
	echo "Backing up system files..."
	sudo rsync -ax --delete \
		/var/spool/cron/ \
		/mnt/nas-backup/home/cron/
	echo "Backup completed successfully"
	echo "----------------------------------------"
} >>"$LOG_FILE" 2>&1

dconf dump / >/mnt/nas-backup/home/pop_os_settings_backup.ini
