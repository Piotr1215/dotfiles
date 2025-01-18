#!/bin/bash
set -eo pipefail
LOG_FILE="$HOME/backup.log"
LOCK_FILE="/tmp/backup.lock"
echo "" >"$LOG_FILE"

if [ -f "$LOCK_FILE" ]; then
	echo "Backup already in progress" >>"$LOG_FILE"
	exit 1
fi
if ! mountpoint -q /mnt/nas-backup; then
	echo "NAS is not mounted. Exiting." >>"$LOG_FILE"
	exit 1
fi

export DISPLAY=:$(ls /tmp/.X11-unix/* | sed 's#/tmp/.X11-unix/X##')
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

# Create lock file
touch "$LOCK_FILE"
touch "$LOG_FILE"
echo "" >"$LOG_FILE"
# Cleanup on exit
trap 'rm -f $LOCK_FILE' EXIT

RSYNC_OPTS=(
	-ax           # Archive mode + preserve extended attributes
	--delete      # Delete extraneous files from dest dirs
	--no-owner    # Don't preserve owner
	--no-group    # Don't preserve group
	--stats       # Show final statistics
	--partial     # Keep partially transferred files
	--sparse      # Handle sparse files efficiently
	--compress    # Compress file data during transfer
	--info=stats0 # Minimal output statistics
	--progress    # Show simple progress
)

{
	date
	echo "Backing up system files..."
	rsync "${RSYNC_OPTS[@]}" \
		--exclude-from="$HOME/.backup_patterns" \
		"$HOME/" \
		/mnt/nas-backup/home/

	echo "Backing up cron jobs..."
	sudo rsync "${RSYNC_OPTS[@]}" \
		/var/spool/cron/ \
		/mnt/nas-backup/home/cron/

	echo "Backing up systemd files..."
	sudo rsync "${RSYNC_OPTS[@]}" \
		/etc/systemd/ \
		/mnt/nas-backup/home/systemd_backup/

	echo "Backing up OBS Studio settings..."
	sudo rsync "${RSYNC_OPTS[@]}" \
		/home/decoder/.var/app/com.obsproject.Studio/config \
		/mnt/nas-backup/home/obs/

	echo "Backup env files..."
	restic backup \
		/home/decoder/.envrc \
		/home/decoder/dev/.envrc \
		/home/decoder/loft/.envrc \
		/home/decoder/.ssh/ \
		/etc/fstab \
		/home/decoder/loft/.nvimrc
	restic forget --keep-last 2 --prune

	echo "Backing up Gnome settings"
	dconf dump / >/mnt/nas-backup/home/pop_os_settings_backup.ini
	backup_size=$(du -sh /mnt/nas-backup/home/ | cut -f1)
	echo "Total backup size: $backup_size" >>"$LOG_FILE"
	echo "Backup completed successfully"
	echo "----------------------------------------"
} >>"$LOG_FILE" 2>&1

dunstify \
	--timeout 1000 \
	--action="default,Open Log" \
	--icon=drive-harddisk \
	"Backup Complete" \
	"System backup has finished successfully" 2>/dev/null | {
	read -r response
	if [ "$response" = "default" ]; then
		alacritty -e nvim -c "nnoremap q :q<CR>" "$HOME/backup.log"
	fi
} &
