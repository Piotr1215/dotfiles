#!/usr/bin/env bash
set -eo pipefail

# =============================================================================
# Enhanced backup script with configuration-based backup sources
#
# HOW TO ADD NEW BACKUP SOURCES:
# 1. For rsync-based backups: Add a new entry to the BACKUP_SOURCES array
#    Format: "name|source_path|destination_path|need_sudo|extra_options"
#    Example: "photos|/home/user/Photos|/mnt/backup/photos|false|--exclude=raw"
#
# 2. For restic-based backups: Add a new path to the RESTIC_SOURCES array
#    Example: "/home/user/important-document.txt"
#
# 3. For special backups (custom commands): Add to the SPECIAL_BACKUPS associative array
#    Format: ["Backup Name"]="command to execute"
#    Example: ["Firefox profiles"]="tar -czf \"$HOME_BACKUP/firefox.tar.gz\" ~/.mozilla"
# =============================================================================

# Configuration section
BACKUP_ROOT="/mnt/nas-backup"
HOME_BACKUP="${BACKUP_ROOT}/home"
DEV_BACKUP="${BACKUP_ROOT}/dev"
SECURE_STORE="${BACKUP_ROOT}/secure-store"
LOG_FILE="$HOME/backup.log"
LOCK_FILE="/tmp/backup.lock"
USER_HOME="$HOME"
BACKUP_PATTERNS_FILE="$HOME/.backup_patterns"

# Notification + health-tracking configuration
NOTIFY_EMAIL="piotrzan@gmail.com"
SUCCESS_STAMP="$HOME/.local/state/backup-last-success"
# Restic needs its password from a file in cron (direnv/.envrc is not loaded there)
export RESTIC_PASSWORD_FILE="$HOME/.config/restic/password"

# Collect non-fatal component failures so one summary alert is sent at the end
declare -a FAILED=()
record_failure() {
	FAILED+=("$1")
	log "ERROR" "$1"
}

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
		for ((i = max_logs; i > 0; i--)); do
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
		record_failure "$cmd_description failed"
		return 1
	fi
	log "INFO" "$cmd_description backup completed successfully"
	return 0
}

# Send a failure alert across every channel. Each channel is best-effort and
# must never abort the script, hence the trailing `|| true` / `2>/dev/null`.
notify_all() {
	local summary="$1"
	local body="${2:-$summary}"
	local host
	host=$(hostname)

	# Desktop popup (only works when logged into the graphical session)
	dunstify --timeout 15000 --urgency=critical --icon=dialog-error \
		"Backup FAILED on $host" "$summary" 2>/dev/null || true

	# Email via msmtp (reliable from cron; body carries the log tail)
	printf 'Subject: [backup] FAILED on %s\nFrom: %s\nTo: %s\n\n%s\n' \
		"$host" "$NOTIFY_EMAIL" "$NOTIFY_EMAIL" "$body" |
		msmtp "$NOTIFY_EMAIL" 2>>"$LOG_FILE" || true
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
	local available_space
	available_space=$(df -m "$BACKUP_ROOT" | awk 'NR==2 {print $4}')
	if [[ $available_space -lt $min_space_mb ]]; then
		log "ERROR" "Insufficient disk space on backup target ($available_space MB)"
		notify_error "Low disk space on backup target: $available_space MB"
		return 1
	fi
	log "INFO" "Disk space check passed: $available_space MB available"
	return 0
}

# Setup display for notifications
display_num=$(find /tmp/.X11-unix/ -type s -name "X*" | head -n 1 | sed 's#/tmp/.X11-unix/X##')
export DISPLAY=":${display_num}"
user_id=$(id -u)
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${user_id}/bus"

# Create lock file
touch "$LOCK_FILE"
rotate_logs
log "INFO" "Starting backup process"

# Initialize exit code variable
exit_code=0

# Cleanup on exit
trap 'exit_code=$?; rm -f "$LOCK_FILE"; log "INFO" "Backup process ended"; if [ "$exit_code" -ne 0 ]; then notify_all "Backup ABORTED early (exit $exit_code)" "Backup on $(hostname) aborted with exit status $exit_code before completing.

--- full run log ---
$(cat "$LOG_FILE")"; fi' EXIT

# Check disk space before starting
check_disk_space || exit 1

# Configure rsync options
RSYNC_OPTS=(
	-ax                          # Archive mode + preserve extended attributes
	--delete                     # Delete extraneous files from dest dirs
	--no-owner                   # Don't preserve owner
	--no-group                   # Don't preserve group
	--stats                      # Show final statistics
	--partial                    # Keep partially transferred files
	--sparse                     # Handle sparse files efficiently
	--compress                   # Compress file data during transfer
	--info=stats2                # Minimal output statistics
	--filter='dir-merge,- .gitignore' # Respect .gitignore in each directory
)

# Add bandwidth limiting during business hours
hour=$(date +%-H)
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

# Define backup sources in an array for easy addition/modification
# Format: "name|source_path|destination_path|need_sudo|extra_options"
declare -a BACKUP_SOURCES=(
	"system files|$USER_HOME/|$HOME_BACKUP/|false|--exclude-from=$BACKUP_PATTERNS_FILE"
	"cron jobs|/var/spool/cron/|$HOME_BACKUP/cron/|true|"
	"systemd files (system)|/etc/systemd/|$HOME_BACKUP/systemd_backup/system/|true|"
	"systemd files (user)|$HOME/.config/systemd/user/|$HOME_BACKUP/systemd_backup/user/|false|"
	"OBS Studio settings|/home/decoder/.var/app/com.obsproject.Studio/config|$HOME_BACKUP/obs/|true|"
	"dev folder|/home/decoder/dev/|$DEV_BACKUP/|true|--chmod=D+w --include=**/.claude/*** --include=**/.claude/ --exclude=*-worktrees/ --exclude=*worktree*/ --exclude=.git/ --exclude=node_modules/ --exclude=venv/ --exclude=.venv/ --exclude=.env --exclude=.envrc --exclude=*.pyc --exclude=__pycache__/ --exclude=dist/ --exclude=build/ --exclude=*.log --exclude=target/ --exclude=.pytest_cache/"
	"loft folder|/home/decoder/loft/ops/|$DEV_BACKUP/loft/ops/|true|--chmod=D+w --include=**/.claude/*** --include=**/.claude/ --exclude=.git/ --exclude=node_modules/ --exclude=venv/ --exclude=.venv/ --exclude=.env --exclude=.envrc --exclude=*.pyc --exclude=__pycache__/ --exclude=dist/ --exclude=build/ --exclude=*.log --exclude=target/ --exclude=.pytest_cache/"
        "argos scripts|/home/decoder/.config/argos/|$HOME_BACKUP/argos/|false|"
	"TLP CPU config|/etc/tlp.d/|$HOME_BACKUP/tlp/|true|"
	# "local mail storage|/home/decoder/.local/share/mail|/mnt/nas-mail/current|false|--delete"
	"zoxide database|/home/decoder/.local/share/zoxide/|$HOME_BACKUP/zoxide/|false|"
	"music library|/home/decoder/music/|$HOME_BACKUP/music/|false|"
	"eve preview manager config|/home/decoder/.config/eve-preview-manager/|$HOME_BACKUP/eve-preview-manager/|false|"
)

# Function to perform backup from configuration
perform_backup() {
	local config="$1"
	local name source_path destination_path need_sudo extra_options

	# Parse configuration
	IFS='|' read -r name source_path destination_path need_sudo extra_options <<<"$config"

	# Execute with or without sudo
	if [[ "$need_sudo" == "true" ]]; then
		if [[ -n "$extra_options" ]]; then
			backup_with_check "$name" sudo rsync "${RSYNC_OPTS[@]}" $extra_options $source_path "$destination_path"
		else
			backup_with_check "$name" sudo rsync "${RSYNC_OPTS[@]}" $source_path "$destination_path"
		fi
	else
		if [[ -n "$extra_options" ]]; then
			backup_with_check "$name" rsync "${RSYNC_OPTS[@]}" $extra_options $source_path "$destination_path"
		else
			backup_with_check "$name" rsync "${RSYNC_OPTS[@]}" $source_path "$destination_path"
		fi
	fi
}

{
	log "INFO" "Backup started at $(date)"

	# Process all backup sources
	for backup_src in "${BACKUP_SOURCES[@]}"; do
		perform_backup "$backup_src"
	done

	# Define restic backup sources
	declare -a RESTIC_SOURCES=(
		"/home/decoder/.envrc"
		"/home/decoder/.claude.json"
		"/home/decoder/.claude/"
		"/home/decoder/dev/.envrc"
		"/home/decoder/loft/.envrc"
		"/home/decoder/.ssh/"
		"/home/decoder/.zsh/completions/"
		"/etc/fstab"
		"/home/decoder/loft/.nvimrc"
		"/home/decoder/dev/cv-pipeline/jobs.db"
		"/home/decoder/.local/share/keyrings/"
		"/home/decoder/.local/bin/get_pw"
		# Secret stores. None of these are caught by the home rsync sweep above:
		# ~/.backup_patterns ends in `- /*`, so anything not explicitly `+`-included
		# is dropped, and all three were silently unbacked up until 2026-07-15.
		#
		# ~/.gnupg is not optional here. The pass store is GPG ciphertext and these
		# private keys are the only thing that opens it, so backing up one without
		# the other restores nothing. Key material goes through restic (encrypted
		# repo) rather than the NAS rsync, which lands plaintext on the share.
		"/home/decoder/.gnupg/"
		"/home/decoder/.password-store/"
		# ~/.secrets: the .age files are re-derivable from Bitwarden through the
		# offline X25519 backup key, but .descriptions (the labels the Ctrl+Alt+P
		# picker renders) exists nowhere else.
		"/home/decoder/.secrets/"
	)

	# Find and add all CLAUDE.md files from dev and loft directories (excluding worktrees)
	while IFS= read -r -d '' claude_file; do
		RESTIC_SOURCES+=("$claude_file")
	done < <(find /home/decoder/dev /home/decoder/loft -maxdepth 3 -name "CLAUDE.md" \
		-not -path "*-worktrees/*" -not -path "*worktree*" -print0 2>/dev/null)

	# Work account overlay (#91): its auth (.claude.json) and session history
	# (projects/) are irreplaceable and live ONLY in this machine, never in the
	# ~/.claude git repo. Shared content is symlinked back to ~/.claude (already
	# backed up above), so only the real per-account files need adding here.
	# Guarded so personal-only machines without the overlay don't fail the backup.
	if [[ -d "/home/decoder/.claude-work" ]]; then
		[[ -f "/home/decoder/.claude-work/.claude.json" ]] && RESTIC_SOURCES+=("/home/decoder/.claude-work/.claude.json")
		[[ -d "/home/decoder/.claude-work/projects" ]] && RESTIC_SOURCES+=("/home/decoder/.claude-work/projects/")
	fi

	# Backup env files with restic
	log "INFO" "Backing up env files with restic..."
	if restic backup "${RESTIC_SOURCES[@]}"; then
		log "INFO" "Restic backup completed successfully"
	else
		record_failure "restic env/secrets backup"
	fi

	# Maintain restic repo. These are guarded so a maintenance failure can never
	# abort the script (set -e) before the special backups below run.
	log "INFO" "Pruning old restic snapshots..."
	restic forget --keep-last 2 --prune || record_failure "restic forget/prune"

	# Check restic repository integrity occasionally (weekly)
	if [[ $(date +%u) -eq 7 ]]; then
		log "INFO" "Performing weekly restic integrity check..."
		restic check --read-data-subset=10% || record_failure "restic integrity check"
	fi

	# Configuration for special backups (not using rsync)
	# Browser profile tars use `|| [ $? -eq 1 ]` so tar's "file changed as we
	# read it" warning (exit 1, normal when the browser is running) is tolerated,
	# while real errors (exit 2+) still register as failures. Without this the
	# run would alert every night a browser is open, training us to ignore alerts.
	declare -A SPECIAL_BACKUPS=(
		["Gnome settings"]="dconf dump / > \"$HOME_BACKUP/pop_os_settings_backup.ini\""
		["LibreWolf profiles"]="tar --warning=no-file-changed -czf \"$HOME_BACKUP/librewolf_profiles.tar.gz\" ~/.var/app/io.gitlab.librewolf-community/.librewolf || [ \$? -eq 1 ]"
		["Chrome profiles"]="tar --warning=no-file-changed -czf \"$HOME_BACKUP/chrome_profiles.tar.gz\" ~/.config/google-chrome || [ \$? -eq 1 ]"
	)

	# Process special backups
	for name in "${!SPECIAL_BACKUPS[@]}"; do
		log "INFO" "Backing up $name..."
		if eval "${SPECIAL_BACKUPS[$name]}"; then
			log "INFO" "$name backup completed successfully"
		else
			record_failure "special backup: $name"
		fi
	done

	# Get backup size
	backup_size=$(du -sh "$HOME_BACKUP/" | cut -f1)
	log "INFO" "Total backup size: $backup_size"

	# Calculate duration
	end_time=$(date +%s)
	duration=$((end_time - start_time))
	log "INFO" "Backup completed in $(printf '%dh:%dm:%ds\n' $((duration / 3600)) $((duration % 3600 / 60)) $((duration % 60)))"

	# Health verdict: alert on any component failure, otherwise stamp success.
	# The stamp is what the watchdog cron reads to detect "never ran" gaps.
	if ((${#FAILED[@]} > 0)); then
		log "ERROR" "${#FAILED[@]} component(s) failed: ${FAILED[*]}"
		notify_all "${#FAILED[@]} backup component(s) failed" "Backup on $(hostname) finished with failures:

$(printf '  - %s\n' "${FAILED[@]}")

--- full run log ---
$(cat "$LOG_FILE")"
	else
		mkdir -p "$(dirname "$SUCCESS_STAMP")"
		date +%s >"$SUCCESS_STAMP"
		log "INFO" "All components succeeded; wrote success stamp"
	fi
	log "INFO" "----------------------------------------"
} >>"$LOG_FILE" 2>&1

# Send success notification with log viewing option (only on a fully clean run;
# failures already alerted via notify_all inside the block above)
if ((${#FAILED[@]} == 0)); then
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
fi
