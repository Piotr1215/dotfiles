#!/bin/bash
set -eo pipefail

# Configuration section
BACKUP_ROOT="/mnt/nas-backup"
HOME_BACKUP="${BACKUP_ROOT}/home"
DEV_BACKUP="${BACKUP_ROOT}/dev"
SECURE_STORE="${BACKUP_ROOT}/secure-store"
LOG_FILE="$HOME/backup.log"
LOCK_FILE="/tmp/backup.lock"
USER_HOME="$HOME"
BACKUP_PATTERNS_FILE="$HOME/.backup_patterns"

# Store start time for performance tracking
start_time=$(date +%s)

# Setup structured logging
log() {
	local level="$1"
	local message="$2"
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >>"$LOG_FILE"
}

# Rotate log files
rotate_logs() {
	local max_logs=5
	if [[ -f "$LOG_FILE" ]]; then
		for ((i = $max_logs; i > 0; i--)); do
			j=$((i - 1))
			[[ -f "$LOG_FILE.$j" ]] && mv "$LOG_FILE.$j" "$LOG_FILE.$i"
		done
		[[ -f "$LOG_FILE" ]] && mv "$LOG_FILE" "$LOG_FILE.0"
	fi
	touch "$LOG_FILE"
	chmod 600 "$LOG_FILE"
}

# Improved error handling for backup operations
backup_with_check() {
	local cmd_description=$1
	shift
	log "INFO" "Backing up $cmd_description..."
	if ! "$@"; then
		log "ERROR" "Failed to backup $cmd_description"
		notify_error "$cmd_description failed"
		return 1
	fi
	log "INFO" "$cmd_description backup completed successfully"
	return 0
}

# Send error notifications
notify_error() {
	dunstify \
		--timeout 15000 \
		--urgency=critical \
		--icon=dialog-error \
		"Backup Error" \
		"$1" 2>/dev/null
}

# Handle stale lock files
if [ -f "$LOCK_FILE" ]; then
	lock_age=$(($(date +%s) - $(stat -c %Y "$LOCK_FILE")))
	if [ $lock_age -gt 86400 ]; then # 24 hours in seconds
		log "WARNING" "Removing stale lock file (age: $lock_age seconds)"
		rm -f "$LOCK_FILE"
	else
		log "INFO" "Backup already in progress"
		exit 1
	fi
fi

# Check if NAS is mounted
if ! mountpoint -q /mnt/nas-backup; then
	log "ERROR" "NAS is not mounted. Exiting."
	exit 1
fi

# Check available disk space
check_disk_space() {
	local min_space_mb=1000
	local available_space=$(df -m "$BACKUP_ROOT" | awk 'NR==2 {print $4}')
	if [[ $available_space -lt $min_space_mb ]]; then
		log "ERROR" "Insufficient disk space on backup target ($available_space MB)"
		notify_error "Low disk space on backup target: $available_space MB"
		return 1
	fi
	log "INFO" "Disk space check passed: $available_space MB available"
	return 0
}

# Setup display for notifications
export DISPLAY=:$(ls /tmp/.X11-unix/* | sed 's#/tmp/.X11-unix/X##')
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

# Create lock file
touch "$LOCK_FILE"
rotate_logs
log "INFO" "Starting backup process"

# Cleanup on exit
trap 'rm -f $LOCK_FILE; log "INFO" "Backup process ended"; exit_status=$?; if [ $exit_status -ne 0 ]; then notify_error "Backup failed with status $exit_status"; fi' EXIT

# Check disk space before starting
check_disk_space || exit 1

# Configure rsync options
RSYNC_OPTS=(
	-ax           # Archive mode + preserve extended attributes
	--delete      # Delete extraneous files from dest dirs
	--no-owner    # Don't preserve owner
	--no-group    # Don't preserve group
	--stats       # Show final statistics
	--partial     # Keep partially transferred files
	--sparse      # Handle sparse files efficiently
	--compress    # Compress file data during transfer
	--info=stats2 # Minimal output statistics
)

# Add bandwidth limiting during business hours
hour=$(date +%H)
if [[ $hour -ge 9 && $hour -lt 17 ]]; then
	RSYNC_OPTS+=(--bwlimit=5000) # 5000 KB/s during working hours
	log "INFO" "Working hours detected, limiting bandwidth"
fi

# Process command line parameters
if [[ "$1" == "--dry-run" ]]; then
	RSYNC_OPTS+=(--dry-run)
	log "INFO" "Running in dry-run mode (no changes will be made)"
fi

# For restic backups
export RESTIC_REPOSITORY="${SECURE_STORE}"

{
	log "INFO" "Backup started at $(date)"

	# Backup system files
	backup_with_check "system files" rsync "${RSYNC_OPTS[@]}" --exclude-from="$BACKUP_PATTERNS_FILE" "$USER_HOME/" "$HOME_BACKUP/"

	# Backup cron jobs
	backup_with_check "cron jobs" sudo rsync "${RSYNC_OPTS[@]}" /var/spool/cron/ "$HOME_BACKUP/cron/"

	# Backup systemd files
	backup_with_check "systemd files" sudo rsync "${RSYNC_OPTS[@]}" /etc/systemd/ ~/.config/systemd/user/ "$HOME_BACKUP/systemd_backup/"

	# Backup OBS Studio settings
	backup_with_check "OBS Studio settings" sudo rsync "${RSYNC_OPTS[@]}" /home/decoder/.var/app/com.obsproject.Studio/config "$HOME_BACKUP/obs/"

	# Backup dev folder
	backup_with_check "dev folder" sudo rsync "${RSYNC_OPTS[@]}" /home/decoder/dev --exclude='.envrc' "$DEV_BACKUP"

	# Backup loft ops
	backup_with_check "loft ops" sudo rsync "${RSYNC_OPTS[@]}" /home/decoder/loft/ops "$DEV_BACKUP/loft"

	# Backup env files with restic
	log "INFO" "Backing up env files with restic..."
	if restic backup \
		/home/decoder/.envrc \
		/home/decoder/dev/.envrc \
		/home/decoder/loft/.envrc \
		/home/decoder/.ssh/ \
		/home/decoder/.zsh/completions/ \
		/etc/fstab \
		/home/decoder/loft/.nvimrc; then
		log "INFO" "Restic backup completed successfully"
	else
		log "ERROR" "Restic backup failed"
	fi

	# Maintain restic repo
	log "INFO" "Pruning old restic snapshots..."
	restic forget --keep-last 2 --prune

	# Check restic repository integrity occasionally (weekly)
	if [[ $(date +%u) -eq 7 ]]; then
		log "INFO" "Performing weekly restic integrity check..."
		restic check --read-data-subset=10%
	fi

	# Backup Gnome settings
	log "INFO" "Backing up Gnome settings..."
	if dconf dump / >"$HOME_BACKUP/pop_os_settings_backup.ini"; then
		log "INFO" "Gnome settings backup completed successfully"
	else
		log "ERROR" "Failed to backup Gnome settings"
	fi

	# Get backup size
	backup_size=$(du -sh "$HOME_BACKUP/" | cut -f1)
	log "INFO" "Total backup size: $backup_size"

	# Calculate duration
	end_time=$(date +%s)
	duration=$((end_time - start_time))
	log "INFO" "Backup completed in $(printf '%dh:%dm:%ds\n' $((duration / 3600)) $((duration % 3600 / 60)) $((duration % 60)))"
	log "INFO" "----------------------------------------"
} >>"$LOG_FILE" 2>&1

# Send success notification with log viewing option
dunstify \
	--timeout 10000 \
	--action="default,Open Log" \
	--icon=drive-harddisk \
	"Backup Complete" \
	"System backup finished successfully in $(printf '%dh:%dm:%ds' $((duration / 3600)) $((duration % 3600 / 60)) $((duration % 60)))" 2>/dev/null | {
	read -r response
	if [ "$response" = "default" ]; then
		alacritty -e nvim -c "nnoremap q :q<CR>" "$LOG_FILE"
	fi
} &
