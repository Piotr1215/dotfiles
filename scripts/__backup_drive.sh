#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/__lib_backup_guard.sh"

DRIVE_MOUNT="${DRIVE_MOUNT:-/mnt/nvme-backup}"
DRIVE_UUID="${DRIVE_UUID:-d74106d0-1b12-4d65-873d-d69ed3a729e6}"
NAS_REPO="${NAS_REPO:-/mnt/nas-backup/secure-store}"
RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE:-$HOME/.config/restic/password}"
DRIVE_STATE_DIR="${DRIVE_STATE_DIR:-$HOME/.local/state/backup-drive}"
MEDIA_SOURCES="${MEDIA_SOURCES:-$HOME/Videos:$HOME/models:$HOME/Downloads:$HOME/music}"
SNAPSHOT_KEEP="${SNAPSHOT_KEEP:-3}"
BACKUP_MAX_DELETES="${BACKUP_MAX_DELETES:-1000}"
LOCK_FILE="${DRIVE_LOCK_FILE:-${TMPDIR:-/tmp}/backup-drive.lock}"
NIGHTLY_LOCK_FILE="${NIGHTLY_LOCK_FILE:-/tmp/backup.lock}"
NTFY_URL="${BACKUP_NTFY_URL:-https://ntfy.sh/homelab-piotr1215-backup}"
unset RESTIC_REPOSITORY RESTIC_PASSWORD

# Print a timestamped message to stdout.
log() {
	local level="$1" message="$2"
	printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$message"
}

# Record a failed part while allowing the other parts to run.
record_failure() {
	FAILED+=("$1")
	log ERROR "$1 failed"
}

# Mirror one source, keeping large deletion sets in an attic.
mirror_media() {
	local src="$1" name dest deletes attic
	name=$(basename "${src%/}")
	dest="$DRIVE_MOUNT/media/$name"
	if [[ ! -d "$src" ]]; then
		log WARNING "Media source missing: $src"
		return 2
	fi
	log INFO "Backing up media: $src"
	if ! mkdir -p "$dest"; then
		return 1
	fi
	local -a run=(rsync -a --delete --exclude=/.attic/ "$src/" "$dest/")
	deletes=$(rsync_deletions "${run[@]}")
	if ((deletes > BACKUP_MAX_DELETES)); then
		attic=".attic/$(date +%Y%m%d-%H%M%S)"
		log WARNING "$name: $deletes deletions exceed $BACKUP_MAX_DELETES; retaining changes in $attic"
		run+=(--backup "--backup-dir=$attic")
	fi
	"${run[@]}" || return 1
	log INFO "Media backup complete: $src"
}

# Succeed when the media mirror differs from its newest snapshot, or has none.
# Media snapshots are taken only on change, so the newest SNAPSHOT_KEEP are that
# many distinct states however old, not that many days (Piotr, 21 Nov: "2 or 3
# good states", no months of history). Comparing with the snapshot itself also
# catches a change whose snapshot failed or was skipped on an earlier run.
media_changed() {
	local out
	local -a snapshots=()
	shopt -s nullglob
	snapshots=("$DRIVE_MOUNT/snapshots/media"@*)
	shopt -u nullglob
	((${#snapshots[@]})) || return 0
	out=$(rsync -a --delete --dry-run --itemize-changes "$DRIVE_MOUNT/media/" "${snapshots[-1]}/" 2>/dev/null) || return 0
	[[ -n "$out" ]]
}

# Create a read-only snapshot and retain the newest configured number.
snapshot_subvolume() {
	local sub="$1" snapshot_dir="$DRIVE_MOUNT/snapshots" path count remove i failed=0
	local -a snapshots=()
	log INFO "Creating snapshot: $sub"
	mkdir -p "$snapshot_dir" || return 1
	path="$snapshot_dir/$sub@$(date +%Y%m%dT%H%M%S)"
	sudo -n btrfs subvolume snapshot -r "$DRIVE_MOUNT/$sub" "$path" || return 1
	log INFO "Snapshot created: $path"
	if [[ ! -r "$snapshot_dir" || ! -x "$snapshot_dir" ]]; then
		log ERROR "Cannot read or traverse snapshot directory: $snapshot_dir"
		return 1
	fi
	shopt -s nullglob
	snapshots=("$snapshot_dir/$sub"@*)
	shopt -u nullglob
	count=${#snapshots[@]}
	remove=$((count - SNAPSHOT_KEEP))
	for ((i = 0; i < remove; i++)); do
		log INFO "Deleting old snapshot: ${snapshots[i]}"
		if sudo -n btrfs subvolume delete "${snapshots[i]}"; then
			log INFO "Old snapshot deleted: ${snapshots[i]}"
		else
			log ERROR "Old snapshot deletion failed: ${snapshots[i]}"
			failed=1
		fi
	done
	return "$failed"
}

# Page the backup ntfy topic, at most once a day for the same failure: a failed
# run retries on every hourly tick.
alert_failure() {
	local text="$1"
	alert_due "$DRIVE_STATE_DIR/alert" "$text" 2>/dev/null || return 0
	curl -fsS -m 20 -H "Priority: high" -H "Tags: warning" -d "serval: drive backup failed: $text" "$NTFY_URL" >/dev/null ||
		log WARNING "ntfy alert failed"
}

# Write the successful run timestamp atomically.
write_stamp() {
	local tmp
	mkdir -p "$DRIVE_STATE_DIR" || return 1
	tmp=$(mktemp "$DRIVE_STATE_DIR/.last-success.XXXXXX") || return 1
	if ! date +%s >"$tmp" || ! mv -f "$tmp" "$DRIVE_STATE_DIR/last-success"; then
		rm -f "$tmp"
		return 1
	fi
}

if (($#)); then
	if (($# == 1)) && [[ "$1" == --help ]]; then
		printf 'Usage: %s [--help]\n' "${0##*/}"
		exit 0
	fi
	printf 'Usage: %s [--help]\n' "${0##*/}" >&2
	exit 2
fi

# One run at a time: the first copy of the NAS repo outlasts the hourly cron
# tick. Exit 75 is a clean skip that __cron_every.sh does not stamp.
exec 9>>"$LOCK_FILE"
if ! flock -n 9; then
	log INFO "Another drive backup holds $LOCK_FILE; skipping"
	exit 75
fi

# The nightly NAS run ends with a prune that takes an exclusive lock and does
# not retry, so a copy holding the NAS repo then would fail it. Wait it out.
nightly_pid=$(cat "$NIGHTLY_LOCK_FILE" 2>/dev/null || true)
if [[ "$nightly_pid" =~ ^[0-9]+$ ]] && kill -0 "$nightly_pid" 2>/dev/null; then
	log INFO "The nightly NAS backup is running (pid $nightly_pid); skipping"
	exit 75
fi

log INFO "Checking drive mount: $DRIVE_MOUNT"
if [[ "$(findmnt -n -o UUID,FSTYPE --mountpoint "$DRIVE_MOUNT" 2>/dev/null || true)" != "$DRIVE_UUID btrfs" ]]; then
	log ERROR "drive not mounted at $DRIVE_MOUNT with the expected UUID $DRIVE_UUID"
	alert_failure "drive not mounted"
	exit 1
fi
log INFO "Drive mount verified: $DRIVE_MOUNT"
start_time=$(date +%s)
declare -a FAILED=() sources=()
held=0 media_succeeded=0 media_failed=0 restic_failed=0
snapshot_config_ok=1 delete_config_ok=1
if [[ ! "$SNAPSHOT_KEEP" =~ ^[0-9]+$ ]]; then
	record_failure "invalid SNAPSHOT_KEEP"
	snapshot_config_ok=0
else
	SNAPSHOT_KEEP=$((10#$SNAPSHOT_KEEP))
fi
if [[ ! "$BACKUP_MAX_DELETES" =~ ^[0-9]+$ ]]; then
	record_failure "invalid BACKUP_MAX_DELETES"
	delete_config_ok=0
else
	BACKUP_MAX_DELETES=$((10#$BACKUP_MAX_DELETES))
fi
if hold_reason=$(backup_hold_reason); then
	held=1
	log WARNING "Media backup held: ${hold_reason:-no reason given}"
elif ((delete_config_ok)); then
	IFS=: read -r -a sources <<<"$MEDIA_SOURCES"
	for src in "${sources[@]}"; do
		rc=0
		mirror_media "$src" || rc=$?
		if ((rc == 0)); then
			media_succeeded=1
		elif ((rc != 2)); then
			record_failure "media $src"
			media_failed=1
		fi
	done
fi

log INFO "Copying restic repository"
if restic -r "$DRIVE_MOUNT/restic/secure-store" --password-file "$RESTIC_PASSWORD_FILE" copy --from-repo "$NAS_REPO" --from-password-file "$RESTIC_PASSWORD_FILE" --retry-lock 30m; then
	log INFO "Restic copy complete"
else
	record_failure "restic copy"
	restic_failed=1
fi
log INFO "Pruning restic repository"
if restic -r "$DRIVE_MOUNT/restic/secure-store" --password-file "$RESTIC_PASSWORD_FILE" forget --retry-lock 30m --group-by host,tags --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --keep-tag keep --keep-tag browser-profiles-2026-09-11 --keep-tag homelab-envrc --prune; then
	log INFO "Restic prune complete"
else
	record_failure "restic forget/prune"
	restic_failed=1
fi
if ((snapshot_config_ok && media_succeeded && !media_failed)); then
	if media_changed; then
		snapshot_subvolume media || record_failure "media snapshot"
	else
		log INFO "Media unchanged since its newest snapshot; no new snapshot"
	fi
fi
if ((snapshot_config_ok && !restic_failed)); then
	snapshot_subvolume restic || record_failure "restic snapshot"
fi

# A held run skipped media, so it must not move the stamp the drill and status
# read as the media mirror's age.
if ((${#FAILED[@]} == 0 && !held)); then
	log INFO "Writing success stamp"
	if write_stamp; then
		log INFO "Success stamp written"
	else
		record_failure "success stamp"
	fi
fi
if ((${#FAILED[@]})); then
	log ERROR "SUMMARY: drive backup FAILED: ${FAILED[*]}"
	alert_failure "${FAILED[*]}"
	exit 1
fi
log INFO "SUMMARY: drive backup complete in $(($(date +%s) - start_time))s"
if ((held)); then
	exit 2
fi
