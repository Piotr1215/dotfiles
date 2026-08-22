#!/usr/bin/env bash
# PROJECT: cron-manager
#
# Weekly full-system rsync to the NAS. Replaces the bare `sudo rsync ...`
# crontab line, which had three faults that cost a 143-minute hang on
# 2026-08-22 and produced a log that was 554 lines of the same error:
#
#   1. Nothing bounded the run. The mount is NFSv4 `hard` (fstab omits `soft`,
#      and `hard` is the default), so a NAS that stops answering blocks the
#      writer in uninterruptible D state forever. rsync's own --timeout=600 is
#      a select() on its socket and never fires from inside a stuck write
#      syscall, which is exactly what happened: 573 lines in the first four
#      seconds, then silence until it was killed 143 minutes later.
#   2. -aAXHv asks the destination for things it cannot do. The export is
#      root_squash, so every chown fails (554 of them, drowning the log), and
#      the volume does not support extended attributes at all
#      (setxattr -> ENOTSUP), so -X can only ever fail once transfers start.
#   3. A live root filesystem always has files that vanish mid-run, which rsync
#      reports as exit 24. That is normal here and must not read as a failure.
#
# Exit codes follow __cron_run.sh: 0 clean, 2 unused, anything else error.
set -eo pipefail
IFS=$'\n\t'

SRC="/"
DEST="${SYSTEM_BACKUP_DEST:-/mnt/nas-backup/system-backup}"
MOUNT_ROOT="${SYSTEM_BACKUP_MOUNT:-/mnt/nas-backup}"
# Wall-clock ceiling. The machine powers off around 23:30 and this starts at
# 13:00, so 90 minutes leaves the day free while still being far longer than a
# healthy incremental run needs.
MAX_SECONDS="${SYSTEM_BACKUP_MAX_SECONDS:-5400}"
# How many transferred entries between heartbeat lines. A full system backup
# names far too many files to log individually, but a silent log is what made
# the hang invisible for two hours, so it still has to show liveness.
HEARTBEAT_EVERY="${SYSTEM_BACKUP_HEARTBEAT_EVERY:-200}"
# Seconds between time-based heartbeats. The count-based sampling above is not
# enough on its own: rsync builds its file list and runs the receiver's
# incremental scan before naming a single file, so a healthy run can be silent
# for minutes, which is indistinguishable from the stall it is meant to expose.
HEARTBEAT_SECONDS="${SYSTEM_BACKUP_HEARTBEAT_SECONDS:-30}"
PREFLIGHT_TIMEOUT="${SYSTEM_BACKUP_PREFLIGHT_TIMEOUT:-20}"

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
		*hard*) log WARN "preflight: mount is 'hard', so a NAS stall blocks in D state; the ${MAX_SECONDS}s ceiling below is the only backstop" ;;
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

# rsync's per-file output is the only liveness signal, but a full system backup
# names hundreds of thousands of entries. Pass every problem line through
# untouched and sample the rest, so the log stays followable and bounded.
# shellcheck disable=SC2016  # awk program: $0 and EVERY are awk, not shell
throttle='
BEGIN { n = 0; start = systime() }
/^(Number|Total|Literal|Matched|File list|sent |total size)/ { print "    " $0; fflush(); next }
/rsync:|rsync error|^WARNING|failed:|No such file/ { print "    ! " $0; fflush(); next }
/^$/ { next }
{
    n++
    if (n % EVERY == 0) {
        printf("    · %d entries, %ds elapsed, at: %s\n", n, systime() - start, $0)
        fflush()
    }
}
END { printf("    · %d entries transferred in %ds\n", n, systime() - start); fflush() }
'

# Cumulative CPU jiffies across every rsync process. /proc/PID/stat is
# world-readable even though rsync runs under sudo, unlike /proc/PID/io, so
# this works from the unprivileged parent.
rsync_cpu_jiffies() {
	local total=0 p u s
	for p in $(pgrep -x rsync 2>/dev/null); do
		read -r u s <<<"$(awk '{print $14, $15}' "/proc/${p}/stat" 2>/dev/null || echo '0 0')"
		total=$(( total + ${u:-0} + ${s:-0} ))
	done
	printf '%s' "$total"
}

rsync_states() {
	ps -o stat= -C rsync 2>/dev/null | tr -d ' ' | sort | uniq -c \
		| awk '{printf "%s×%s ", $1, $2}'
}

# Proof of life, every HEARTBEAT_SECONDS, whether or not rsync is naming files.
# Reports the two things that actually distinguish working from wedged: is any
# rsync burning CPU, and is anything sitting in uninterruptible D state. Three
# consecutive frozen samples with a D-state process is the exact signature of
# the 143-minute hang, so it says so instead of leaving it to be noticed later.
heartbeat() {
	local started="$1" last_cpu=-1 frozen=0 n=0 cpu el states
	while :; do
		sleep "$HEARTBEAT_SECONDS"
		n=$(( n + 1 ))
		cpu="$(rsync_cpu_jiffies)"
		states="$(rsync_states)"
		el=$(( $(date +%s) - started ))
		if [ "$cpu" = "$last_cpu" ]; then
			frozen=$(( frozen + 1 ))
		else
			frozen=0
		fi
		last_cpu="$cpu"
		if [ "$frozen" -ge 3 ] && [ "${states#*D}" != "$states" ]; then
			log WARN "heartbeat ${n}: ${el}s elapsed, rsync cpu FROZEN at ${cpu} jiffies for $(( frozen * HEARTBEAT_SECONDS ))s with a process in D state [${states}]. This is the NFS stall signature; the ${MAX_SECONDS}s ceiling will end it."
		else
			log INFO "heartbeat ${n}: ${el}s elapsed, rsync cpu ${cpu} jiffies, states [${states:-none}]"
		fi
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
	local -a opts=(
		-a --no-owner --no-group
		-H                    # preserve hard links
		-v                    # per-file output, sampled by the throttle above
		--delete
		--partial             # keep partial transfers across a failed run
		--timeout=600         # socket-level stall detection (does not cover D state)
		--stats
		--exclude='/home/*' --exclude='/dev/*' --exclude='/proc/*'
		--exclude='/sys/*' --exclude='/tmp/*' --exclude='/run/*'
		--exclude='/mnt/*' --exclude='/media/*'
		--exclude='/recovery/' --exclude='/lost+found/'
	)

	log INFO "ownership is not preserved: destination is root_squash NFS without xattr support"
	log INFO "wall-clock ceiling ${MAX_SECONDS}s, then SIGTERM and SIGKILL 60s later"
	# ${opts[*]} would join on IFS, which is newline here, so build it explicitly.
	log INFO "running: sudo rsync $(printf '%s ' "${opts[@]}")${SRC} ${DEST}"

	local rc=0
	local started
	started="$(date +%s)"

	heartbeat "$started" &
	local hb_pid=$!

	set +e
	timeout --signal=TERM --kill-after=60 "$MAX_SECONDS" \
		sudo -n rsync "${opts[@]}" "$SRC" "$DEST" 2>&1 \
		| awk -v EVERY="$HEARTBEAT_EVERY" "$throttle"
	rc=${PIPESTATUS[0]}
	set -e

	kill "$hb_pid" 2>/dev/null || true
	wait "$hb_pid" 2>/dev/null || true

	local elapsed=$(( $(date +%s) - started ))

	case "$rc" in
		0)
			log INFO "SUMMARY: backup complete, no errors, ${elapsed}s"
			return 0
			;;
		24)
			# Source files vanishing mid-run is expected on a live root.
			log INFO "SUMMARY: backup complete in ${elapsed}s (rsync 24: some source files vanished during the run, normal for a live root)"
			return 0
			;;
		124|137)
			log ERROR "SUMMARY: backup KILLED at the ${MAX_SECONDS}s ceiling after ${elapsed}s: the NAS stalled and the mount is hard, so rsync could not time out on its own"
			return 1
			;;
		*)
			log ERROR "SUMMARY: backup FAILED with rsync exit ${rc} after ${elapsed}s"
			return 1
			;;
	esac
}

main "$@"
exit $?
