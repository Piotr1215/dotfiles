#!/usr/bin/env bash
# PROJECT: cron-manager
#
# Weekly full-system rsync to the NAS. Replaces the bare `sudo rsync ...`
# crontab line, which had three faults that cost a 143-minute hang on
# 2026-08-22 and produced a log that was 554 lines of the same error:
#
#   1. -aAXHv asks the destination for things it cannot do. The export is
#      root_squash, so every chown fails (554 of them, drowning the log), and
#      the volume does not support extended attributes at all
#      (setxattr -> ENOTSUP), so -X can only ever fail once transfers start.
#   2. The log went silent and a healthy run looked like a stall. -v is
#      --info=name1, which mentions only updated names, so an already-synced
#      subtree printed nothing for 650s. rsync can report all of this itself,
#      so ask it: --info=flist2,name2,del,progress2,stats2.
#   3. A live root filesystem always has files that vanish mid-run, which rsync
#      reports as exit 24. That is normal here and must not read as a failure.
#
# There is no wall-clock ceiling. rsync is idempotent and resumable, so a run
# that is moving is left to finish however long it takes, and a run that fails
# is retried rather than killed. The mount is NFSv4 `hard` (fstab omits `soft`,
# and `hard` is the default), so a NAS that stops answering blocks the writer in
# uninterruptible D state and nothing inside rsync can end that; such a run sits
# until the NAS answers. The --info output above is what makes that visible in
# the log while it is happening.
#
# Exit codes follow __cron_run.sh: 0 clean, 2 unused, anything else error.
set -eo pipefail
IFS=$'\n\t'

SRC="/"
DEST="${SYSTEM_BACKUP_DEST:-/mnt/nas-backup/system-backup}"
MOUNT_ROOT="${SYSTEM_BACKUP_MOUNT:-/mnt/nas-backup}"
PREFLIGHT_TIMEOUT="${SYSTEM_BACKUP_PREFLIGHT_TIMEOUT:-20}"
# Retry budget. rsync resumes with --partial, so a retry picks up where the
# failed attempt stopped instead of starting over.
MAX_ATTEMPTS="${SYSTEM_BACKUP_MAX_ATTEMPTS:-5}"
# How many consecutive failed attempts that moved nothing before giving up.
# Retrying is only worth it while attempts make forward progress; a run that
# fails three times having transferred zero bytes is broken, not slow.
BARREN_LIMIT="${SYSTEM_BACKUP_BARREN_LIMIT:-3}"
RETRY_DELAY="${SYSTEM_BACKUP_RETRY_DELAY:-60}"

# One attempt's rsync output, kept so the end-of-run stats block can be read
# back after the attempt exits. tee writes it while the same output goes to
# stdout live, which is race-free: bash waits for every stage of the pipeline.
RSYNC_LOG="$(mktemp -t system-backup-rsync.XXXXXX)"

# Seconds of ZERO rsync output before the run is called jammed and killed.
# This is not a time limit on the backup. --info=name2 makes rsync name every
# file it examines, unchanged ones included, so a healthy run writes to
# $RSYNC_LOG continuously no matter how long it takes overall. A log that stops
# growing means rsync has stopped doing anything, which on this hard NFS mount
# means it is parked in D state waiting for a NAS that is not answering.
# Observed 2026-08-22: the mount wedged, rsync sat in D burning 6 CPU jiffies
# per 10s, and nothing ended it because rsync's own --timeout is a select() on
# its socket that cannot fire from inside a blocked write.
JAM_SECONDS="${SYSTEM_BACKUP_JAM_SECONDS:-120}"
trap 'rm -f "$RSYNC_LOG"' EXIT

log() {
	printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "${*:2}"
}

# Every NAS touch is bounded. An unbounded probe on a hard mount would hang the
# same way the backup did, just earlier and more confusingly.
preflight() {
	log INFO "preflight: checking ${MOUNT_ROOT}"

	if ! findmnt -T "$MOUNT_ROOT" >/dev/null 2>&1; then
		log ERROR "preflight: ${MOUNT_ROOT} is not a mount point"
		return 1
	fi

	local opts
	opts="$(findmnt -T "$MOUNT_ROOT" -no OPTIONS 2>/dev/null || echo '?')"
	log INFO "preflight: mounted with ${opts}"
	case "$opts" in
		*hard*) log WARN "preflight: mount is 'hard', so a NAS stall blocks the writer in D state and no rsync timeout can end it; such a run sits until the NAS answers" ;;
	esac

	local probe="${MOUNT_ROOT}/.backup-preflight-$$"
	if ! timeout "$PREFLIGHT_TIMEOUT" touch "$probe" 2>/dev/null; then
		log ERROR "preflight: cannot write to ${MOUNT_ROOT} within ${PREFLIGHT_TIMEOUT}s (NAS down, read-only, or already stalled)"
		return 1
	fi
	timeout "$PREFLIGHT_TIMEOUT" rm -f "$probe" 2>/dev/null || true
	log INFO "preflight: ${MOUNT_ROOT} is writable"

	if ! timeout "$PREFLIGHT_TIMEOUT" sudo -n mkdir -p "$DEST" 2>/dev/null; then
		log ERROR "preflight: cannot create ${DEST} (sudo -n unavailable, or NAS stalled)"
		return 1
	fi
	log INFO "preflight: destination ${DEST} ready"
	return 0
}

# One number out of rsync's own end-of-run stats block (--info=stats2), which is
# the only trustworthy answer to "did this attempt move anything". rsync prints
# the numbers with thousands separators, so strip every non-digit. An attempt
# that died before printing its summary has no matching line and reads as 0,
# which is exactly the "made no progress" the retry loop is looking for.
rsync_stat() {
	local v
	v="$(awk -v label="$1:" 'index($0, label) == 1 { gsub(/[^0-9]/, "", $0); print; exit }' "$RSYNC_LOG" 2>/dev/null || true)"
	printf '%s' "${v:-0}"
}

human_bytes() {
	local b="${1:-0}"
	if   [ "$b" -lt 1024 ]; then printf '%sB' "$b"
	elif [ "$b" -lt 1048576 ]; then printf '%sK' "$(( b / 1024 ))"
	elif [ "$b" -lt 1073741824 ]; then printf '%sM' "$(( b / 1048576 ))"
	else printf '%sG' "$(( b / 1073741824 ))"
	fi
}

# Kill this job's rsync when it stops producing output, so the retry loop below
# can take over. SIGKILL, not SIGTERM: a process in uninterruptible D sleep on a
# hard NFS mount does not take TERM, and Linux makes NFS waits killable by KILL
# specifically. Scoped by destination so a concurrent __backup rsync is untouched.
jam_watch() {
	local last=-1 size still=0 p
	while :; do
		sleep 15
		size=$(stat -c %s "$RSYNC_LOG" 2>/dev/null || echo 0)
		if [ "$size" = "$last" ]; then still=$(( still + 15 )); else still=0; fi
		last="$size"
		[ "$still" -ge "$JAM_SECONDS" ] || continue
		log ERROR "JAMMED: rsync produced no output for ${still}s. Killing it so the run retries."
		for p in $(pgrep -x rsync 2>/dev/null); do
			case "$(tr '\0' ' ' <"/proc/${p}/cmdline" 2>/dev/null)" in
				*"$DEST"*) sudo -n kill -KILL "$p" 2>/dev/null || true ;;
			esac
		done
		return 0
	done
}

main() {
	log INFO "=== system backup starting: ${SRC} -> ${DEST}"

	preflight || {
		log ERROR "SUMMARY: backup aborted in preflight, nothing was transferred"
		return 1
	}

	# -a minus the two things this destination provably cannot do:
	#   --no-owner/--no-group  : export is root_squash, chown always fails
	#   no -X                  : volume returns ENOTSUP for extended attributes
	# Ownership is therefore NOT preserved in this copy. A bare-metal restore
	# from it needs ownership reapplied separately.
	# shellcheck disable=SC2054  # the commas belong to --info=, not to the array
	local -a opts=(
		-a --no-owner --no-group
		-x                    # one file system. Without it rsync descends into
		                      # all 19 squashfs snap mounts under /snap: 247,354
		                      # files instead of 49, every one a read-only image
		                      # snapd reinstalls on demand. __backup.sh has used
		                      # -ax since it was written; this script never did,
		                      # which is why a full pass never completed.
		-H                    # preserve hard links
		--delete
		--partial             # a failed attempt resumes rather than restarts
		--timeout=600         # rsync's own I/O stall detection (a select() on its
		                      # socket, so it cannot fire from inside a blocked
		                      # write to a hard NFS mount; exit 30 here retries)
		--outbuf=L            # line buffered, so the log follows live under tail -f
		# Ask rsync for the report instead of inferring one. NAME2 mentions
		# unchanged names as well as updated ones, which is what keeps an
		# already-synced subtree from looking like a stall. FLIST2 shows the
		# file-list build, DEL the deletions, PROGRESS2 the running total, and
		# STATS2 the end summary that the retry loop below reads back.
		--info=flist2,name2,del,progress2,stats2
		--exclude='/home/*' --exclude='/dev/*' --exclude='/proc/*'
		--exclude='/sys/*' --exclude='/tmp/*' --exclude='/run/*'
		--exclude='/mnt/*' --exclude='/media/*'
		--exclude='/recovery/' --exclude='/lost+found/'
		# Rebuildable bulk: 156G of the 169G this job used to copy, measured
		# 2026-08-22. Every byte of it is reproducible from a registry, from
		# apt, or from a kernel package, and hauling it weekly across a hard
		# NFS mount is why a full pass had not completed since 2024-12-22.
		# /var/lib/containerd alone was 115G, 68% of the whole job.
		--exclude='/var/lib/containerd'   # 115G  container image layers
		--exclude='/var/lib/docker'       #  11G  container image layers
		--exclude='/usr'                  #  24G  apt reinstalls all of it
		--exclude='/var/cache'            #   4G  cache by definition
		--exclude='/var/lib/snapd'        # 1.2G  snapd redownloads
		--exclude='/boot'                 # 874M  regenerated on kernel install
		# 32,168 files for 3.8G, all of it vendor installer output: az (29,804
		# files alone), zoom, google, Signal, 1Password, Bitwarden, opentofu.
		# Every one reinstalls from a package or a vendor script, and none of it
		# holds config or data (that lives in ~ and is __backup.sh's job). It is
		# also the worst possible shape for NFS: 21KB average file, so the cost
		# is round trips, not bytes. Same reasoning that excluded /usr.
		--exclude='/opt'                  # 3.8G  vendor installs, 32k tiny files
		# /root is 19,583 files and 19,523 of them are cache. Excluding these two
		# leaves ~60 real files: root's shell config, ssh, and the dotfiles that
		# are the only reason to back /root up at all. npm repopulates its cache
		# on first install, which is what a cache is for.
		--exclude='/root/.npm'            # 2.0G  15,905 files, npm cache
		--exclude='/root/.cache'          # 650M   3,618 files, cache by name
	)

	log INFO "ownership is not preserved: destination is root_squash NFS without xattr support"
	# ${opts[*]} would join on IFS, which is newline here, so build it explicitly.
	log INFO "running: sudo rsync $(printf '%s ' "${opts[@]}")${SRC} ${DEST}"

	local started attempt=0 barren=0 rc=0 elapsed=0 jam_pid=
	local files=0 bytes=0 total_files=0 total_bytes=0
	started="$(date +%s)"

	while :; do
		attempt=$(( attempt + 1 ))
		log INFO "rsync attempt ${attempt}/${MAX_ATTEMPTS}"
		: > "$RSYNC_LOG"

		set +e
		jam_watch &
		jam_pid=$!
		sudo -n rsync "${opts[@]}" "$SRC" "$DEST" 2>&1 | tee "$RSYNC_LOG"
		rc=${PIPESTATUS[0]}
		kill "$jam_pid" 2>/dev/null || true
		wait "$jam_pid" 2>/dev/null || true
		set -e

		files="$(rsync_stat 'Number of regular files transferred')"
		bytes="$(rsync_stat 'Total transferred file size')"
		total_files=$(( total_files + files ))
		total_bytes=$(( total_bytes + bytes ))
		elapsed=$(( $(date +%s) - started ))

		case "$rc" in
			0)
				log INFO "SUMMARY: backup complete in ${elapsed}s over ${attempt} attempt(s), ${total_files} files / $(human_bytes "$total_bytes") transferred, no errors"
				return 0
				;;
			24)
				# Source files vanishing mid-run is expected on a live root.
				log INFO "SUMMARY: backup complete in ${elapsed}s over ${attempt} attempt(s), ${total_files} files / $(human_bytes "$total_bytes") transferred (rsync 24: some source files vanished during the run, normal for a live root)"
				return 0
				;;
		esac

		log ERROR "attempt ${attempt} failed with rsync exit ${rc} after ${elapsed}s, having transferred ${files} files / $(human_bytes "$bytes")"

		if [ "$files" -eq 0 ] && [ "$bytes" -eq 0 ]; then
			barren=$(( barren + 1 ))
		else
			barren=0
		fi

		if [ "$barren" -ge "$BARREN_LIMIT" ]; then
			log ERROR "SUMMARY: backup FAILED after ${attempt} attempts in ${elapsed}s, the last ${barren} transferring nothing at all (rsync exit ${rc}); ${total_files} files / $(human_bytes "$total_bytes") transferred in total"
			return 1
		fi

		if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
			log ERROR "SUMMARY: backup FAILED after ${attempt} attempts in ${elapsed}s, last rsync exit ${rc}; ${total_files} files / $(human_bytes "$total_bytes") transferred in total"
			return 1
		fi

		log WARN "retrying in ${RETRY_DELAY}s; --partial means the next attempt resumes rather than restarts"
		sleep "$RETRY_DELAY"
	done
}

main "$@"
exit $?
