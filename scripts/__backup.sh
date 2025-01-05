#!/bin/bash
set -eo pipefail
LOG_FILE="$HOME/backup.log"
LOCK_FILE="/tmp/backup.lock"
echo "" >"$LOG_FILE"
# Exit if already running
if [ -f "$LOCK_FILE" ]; then
	echo "Backup already in progress" >>"$LOG_FILE"
	exit 1
fi

if ! mountpoint -q /mnt/nas-backup; then
	echo "NAS is not mounted. Exiting." >>"$LOG_FILE"
	exit 1
fi

# Create lock file
touch "$LOCK_FILE"
touch "$LOG_FILE"
echo "" >"$LOG_FILE"

# Cleanup on exit
trap 'rm -f $LOCK_FILE' EXIT

{
	date
	echo "Backing up system files..."

	rsync -ax --delete \
		--no-owner --no-group \
		--info=backup,stats3 \
		--exclude-from="$HOME/.backup_patterns" \
		--stats \
		"$HOME/" \
		/mnt/nas-backup/home/

	echo "Backing up cron jobs..."
	sudo rsync -ax --delete \
		--no-owner --no-group \
		--info=stats1 \
		/var/spool/cron/ \
		/mnt/nas-backup/home/cron/

	echo "Backing up systemd files..."
	sudo rsync -ax --delete \
		--no-owner --no-group \
		--info=stats1 \
		/etc/systemd/ \
		/mnt/nas-backup/home/systemd_backup/

	echo "Backing up OBS Studio settings..."
	sudo rsync -ax --delete \
		--no-owner --no-group \
		--info=stats1 \
		/home/decoder/.var/app/com.obsproject.Studio/config \
		/mnt/nas-backup/home/obs/
	echo "Backup env files..."
	restic backup /home/decoder/.envrc
	restic backup /home/decoder/dev/.envrc
	restic backup /home/decoder/loft/.envrc
	restic backup /home/decoder/.ssh/
	restic backup /etc/fstab
	restic forget --keep-last 1 --prune

	echo "Badking up Gnome settings"
	dconf dump / >/mnt/nas-backup/home/pop_os_settings_backup.ini
	echo "Backup completed successfully"
	echo "----------------------------------------"
} >>"$LOG_FILE" 2>&1

dunstify \
	--timeout 1000 \
	--action="default,Open Log" \
	--icon=drive-harddisk \
	"Backup Complete" \
	"System backup has finished successfully" &&
	alacritty -e nvim \
		-c "nnoremap q :q<CR>" \
		"$HOME/backup.log"
