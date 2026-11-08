#!/usr/bin/env bash
# Mirror handoff briefs and Gordon state to the NAS and alert on stale task backups.
#
# WHY: on 2026-11-07 an agent test ran `rm -rf ~`, and the task DB had reached
# no backup since 8 Feb. Piotr, 8 Nov: "the mirror should be removed if we have
# taskchampion sync (and restore works)". Tasks, handoffs included, now sync to
# the homelab TaskChampion server every 5 minutes, and the weekly drill restores
# them from it. Handoff briefs and Gordon state are files TaskChampion does not
# carry, so they keep this mirror.
#
#   mirror    every 5 minutes from cron: briefs and Gordon state to the NAS with
#             rsync and no --delete, so a file gone from the source stays there.
#   daily     __backup.sh at 20:00: a restic snapshot of the DB, briefs and state.
#   check     every 5 minutes: ntfy page when the NAS is gone, the last good sync
#             is over 15 minutes old, the state dirs over 30, or the daily
#             snapshot over 26 hours. Exits 2 on an alert, the cron wrapper's hit.
#
# Restore, never in place:
#   tasks:  a scratch TASKDATA plus the sync settings, then `task sync`
#           (__backup_drill.sh --layer taskchampion does exactly this)
#   state:  /mnt/nas-backup/taskwarrior-mirror/state/
#   daily:  restic restore latest --path ~/.local/share/task-backups
#           --target <scratch dir> (RESTIC_REPOSITORY=/mnt/nas-backup/secure-store,
#           RESTIC_PASSWORD_FILE=~/.config/restic/password)
set -eo pipefail

TASK_DB="${TASK_DB:-$HOME/.task/taskchampion.sqlite3}"
IFS=: read -r -a DIRS <<<"${TASK_BACKUP_DIRS:-$HOME/.local/state/taskwarrior/briefs:$HOME/.local/state/gordon}"
NAS="${TASK_BACKUP_NAS:-/mnt/nas-backup}"
MIRROR="$NAS/taskwarrior-mirror"
# Staging lives in RAM: the copy is transient and needs no disk write.
STAGE="${TASK_BACKUP_STAGE:-/dev/shm/task-backup-$(id -u)}"
NTFY_TOPIC="${TASK_BACKUP_NTFY:-https://ntfy.sh/homelab-piotr1215-backup}"
SYNC_MAX_AGE="${TASK_SYNC_MAX_AGE:-900}"
SYNC_LOG="${CRON_STATE_DIR:-$HOME/.local/state/cron-jobs}/__task_sync.log"
DIRS_MAX_AGE="${TASK_DIRS_MAX_AGE:-1800}"
# The path __backup.sh puts the daily DB copy under; it marks the snapshots.
SNAPSHOT_PATH="${TASK_SNAPSHOT_PATH:-$HOME/.local/share/task-backups}"
SNAPSHOT_MAX_AGE="${TASK_SNAPSHOT_MAX_AGE:-93600}"
REALERT_AFTER="${TASK_REALERT_AFTER:-21600}"
export RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-$NAS/secure-store}"
[[ -n "$RESTIC_PASSWORD" ]] || export RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE:-$HOME/.config/restic/password}"

# nas_ready: the NAS is mounted and takes a write within 20 s. mountpoint alone
# passes on the autofs stub while the NAS is unreachable (see __backup.sh).
nas_ready() {
	mountpoint -q "$NAS" || return 1
	# shellcheck disable=SC2016 # $1 expands in the inner bash
	timeout -k 5 20 bash -c 'mkdir -p "$1" && touch "$1/.probe"' _ "$MIRROR" 2>/dev/null
}

# fail <message>: record why the mirror stopped, for the check's page, in
# ERR_FILE (.last-error for the DB, .dirs-error for the state dirs).
fail() {
	printf '%s %s\n' "$(date '+%F %T')" "$1" >"$MIRROR/${ERR_FILE:-.last-error}" 2>/dev/null || true
	echo "ERROR: $1" >&2
}

# mirror_dirs: add and update files on the NAS, never delete. A missing source
# dir stops the mirror. rsync exit 24 (a file vanished mid-run) is normal here.
mirror_dirs() {
	local d rc
	for d in "${DIRS[@]}"; do
		if [[ ! -d "$d" ]]; then
			ERR_FILE=.dirs-error fail "$d is missing, NAS copy kept"
			return 1
		fi
		rc=0
		timeout -k 5 900 rsync -rlpt --mkpath "$d/" "$MIRROR/state$d/" || rc=$?
		if ((rc != 0 && rc != 24)); then
			ERR_FILE=.dirs-error fail "rsync of $d failed (exit $rc)"
			return 1
		fi
	done
}

# Serialize state directory mirrors; an overlapping run can skip safely.
cmd_mirror() {
	if ! nas_ready; then
		echo "ERROR: NAS $NAS is not mounted or not writable" >&2
		return 1
	fi
	exec 9>"$STAGE/mirror-dirs.lock"
	flock -n 9 || return 0
	if mirror_dirs; then
		date +%s >"$MIRROR/.dirs-ok-at"
		rm -f "$MIRROR/.dirs-error"
	else
		return 1
	fi
}

# The cron wrapper appends an end line only after the task command exits.
# Its JSON state holds only the latest run, so a failure would erase the time
# of the previous success. Read only the wrapper's success timestamp.
last_sync() {
	local stamp
	stamp=$(sed -nE 's/^\[([^]]+)\] \[INFO\] run end: exit=0 state=no-hit duration=[0-9]+s$/\1/p' "$SYNC_LOG" 2>/dev/null | tail -n 1 || true)
	if [[ -n "$stamp" ]]; then
		date -d "$stamp" +%s 2>/dev/null || echo 0
	else
		echo 0
	fi
}

# newest_snapshot: epoch of the newest snapshot holding SNAPSHOT_PATH, 0 for
# none, empty when the repository cannot be read.
newest_snapshot() {
	restic snapshots --no-lock --no-cache -q --path "$SNAPSHOT_PATH" --latest 1 --json 2>/dev/null |
		python3 -I -c '
import datetime, json, sys
times = [datetime.datetime.fromisoformat(s["time"]).timestamp() for s in json.load(sys.stdin) or []]
print(int(max(times, default=0)))' 2>/dev/null || true
}

# page <ntfy priority> <ntfy tags> <message>: phone and desktop, best effort.
page() {
	curl -s -o /dev/null --connect-timeout 5 -m 15 -H "Title: Task backup on $(hostname)" \
		-H "Priority: $1" -H "Tags: $2" -d "$3" "$NTFY_TOPIC" || true
	notify-send --urgency="$([[ $1 == high ]] && echo critical || echo normal)" \
		"Task backup on $(hostname)" "$3" 2>/dev/null || true
}

cmd_check() {
	local problems=() kinds=() now up sync_at dirs_at snap msg alerted="$STAGE/alerted"
	now=$(date +%s)
	up=${TASK_BACKUP_UPTIME:-$(cut -d. -f1 /proc/uptime)}
	[[ -f "$TASK_DB" ]] || { problems+=("no task DB at $TASK_DB"); kinds+=(db); }
	sync_at=$(last_sync)
	if ((now - sync_at > SYNC_MAX_AGE && up > SYNC_MAX_AGE)); then
		if ((sync_at == 0)); then
			problems+=("TaskChampion sync has no recorded success")
		else
			problems+=("TaskChampion sync last succeeded $(((now - sync_at) / 60)) min ago")
		fi
		kinds+=(sync)
	fi
	if ! nas_ready; then
		problems+=("NAS $NAS is not mounted or not writable")
		kinds+=(nas)
	else
		dirs_at=$(cat "$MIRROR/.dirs-ok-at" 2>/dev/null || echo 0)
		if ((now - dirs_at > DIRS_MAX_AGE && up > DIRS_MAX_AGE)); then
			problems+=("briefs and Gordon state last mirrored $(((now - dirs_at) / 60)) min ago: $(cat "$MIRROR/.dirs-error" 2>/dev/null || echo 'no error recorded')")
			kinds+=(dirs)
		fi
		snap=$(newest_snapshot)
		if [[ -z "$snap" ]]; then
			problems+=("cannot list snapshots in $RESTIC_REPOSITORY")
			kinds+=(restic)
		elif ((now - snap > SNAPSHOT_MAX_AGE)); then
			problems+=("newest daily restic snapshot of the task DB is $(((now - snap) / 3600)) h old")
			kinds+=(daily)
		fi
	fi
	if ((${#problems[@]})); then
		msg=$(printf '%s; ' "${problems[@]}")
		msg=${msg%; }
		# Page at once for a new kind of problem, else every REALERT_AFTER.
		if [[ "$(cat "$alerted" 2>/dev/null)" != "${kinds[*]}" ]] ||
			((now - $(stat -c %Y "$alerted") >= REALERT_AFTER)); then
			page high warning "$msg"
			echo "${kinds[*]}" >"$alerted"
		fi
		echo "ALERT: $msg"
		return 2
	fi
	if [[ -f "$alerted" ]]; then
		page default white_check_mark "recovered: sync, state mirror and daily snapshot are current"
		rm -f "$alerted"
	fi
	echo "ok: sync $(((now - sync_at) / 60)) min old, state mirror $(((now - dirs_at) / 60)) min old, daily snapshot $(((now - snap) / 3600)) h old"
}

umask 077
mkdir -p "$STAGE"
case "${1:-}" in
mirror)
	cmd_mirror
	;;
check) cmd_check ;;
*)
	echo "usage: ${0##*/} mirror | check" >&2
	exit 64
	;;
esac
