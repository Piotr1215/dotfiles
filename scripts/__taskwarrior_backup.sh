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

# Off LAN, rsync onto the NFS mount pays one tailnet round trip per file: on
# 2026-11-17, on a phone hotspot, the 22k-file Gordon state hit the 900 s
# timeout (exit 124) every run. pop-os sits on the NAS LAN and mounts the same
# share, so off LAN the mirror rsync goes over ssh to pop-os, as __backup.sh
# does (#181); the dry run took 10 s. The key is pinned on pop-os to
# `rrsync -wo /mnt/nas-backup`, so remote paths are relative to the share.
# The relay is off when TASK_BACKUP_NAS points elsewhere (tests), unless
# TASK_BACKUP_RELAY names one.
NAS_LAN_PROBE="${TASK_BACKUP_LAN_PROBE:-192.168.178.138/2049}"
if [[ -n "${TASK_BACKUP_RELAY+set}" ]]; then
	RELAY="$TASK_BACKUP_RELAY"
elif [[ "$NAS" == /mnt/nas-backup ]]; then
	RELAY="decoder@100.84.38.78:"
else
	RELAY=""
fi
RELAY_SSH="${TASK_BACKUP_RELAY_SSH:-ssh -i $HOME/.ssh/id_ed25519_backup_pop_os -o IdentitiesOnly=yes -o IdentityAgent=none -o BatchMode=yes -o ConnectTimeout=15 -o HostKeyAlias=192.168.178.125 -o UserKnownHostsFile=$HOME/.ssh/known_hosts}"
# Set by pick_route: where mirror_dirs writes, and the rsync options for it.
DEST="$MIRROR"
ROUTE_OPTS=()

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
	# Bounded: off LAN the NFS write can stall with the uplink.
	# shellcheck disable=SC2016 # $1 and $2 expand in the inner bash
	timeout -k 5 20 bash -c 'printf "%s\n" "$2" >"$1"' _ "$MIRROR/${ERR_FILE:-.last-error}" "$(date '+%F %T') $1" 2>/dev/null || true
	echo "ERROR: $1" >&2
}

# mirror_dirs: add and update files on the NAS, never delete. A missing source
# dir stops the mirror. rsync exit 24 (a file vanished mid-run) is normal here.
mirror_dirs() {
	local d rc try
	for d in "${DIRS[@]}"; do
		if [[ ! -d "$d" ]]; then
			ERR_FILE=.dirs-error fail "$d is missing, NAS copy kept"
			return 1
		fi
		# Exit 255 is the relay's ssh failing to connect; off LAN the uplink
		# stalls for a minute at a time, so try again before giving up.
		for try in 1 2 3; do
			rc=0
			timeout -k 5 900 rsync -rlpt --mkpath "${ROUTE_OPTS[@]}" "$d/" "$DEST/state$d/" || rc=$?
			((rc == 255 && ${#ROUTE_OPTS[@]} > 0)) || break
		done
		if ((rc != 0 && rc != 24)); then
			ERR_FILE=.dirs-error fail "rsync of $d failed (exit $rc)"
			return 1
		fi
	done
}

# pick_route: on LAN, or with no relay, write to the NFS mount. Off LAN, write
# through the relay when it answers; if it does not, fall back to the mount.
# Three tries: on the 17 Nov hotspot the uplink stalled most minutes and the
# first ssh connect timed out while the next one went through.
pick_route() {
	local empty try
	if [[ -z "$RELAY" ]] || timeout 3 bash -c ": </dev/tcp/$NAS_LAN_PROBE" 2>/dev/null; then
		echo "route: NFS mount"
		return 0
	fi
	empty=$(mktemp -d "$STAGE/preflight.XXXXXX")
	for try in 1 2 3; do
		if timeout 45 rsync -n -d --timeout=30 -e "$RELAY_SSH" "$empty/" "${RELAY}${MIRROR#"$NAS"/}/" >/dev/null 2>&1; then
			DEST="${RELAY}${MIRROR#"$NAS"/}"
			ROUTE_OPTS=(-e "$RELAY_SSH" --timeout=300)
			echo "route: off LAN, through the pop-os relay (try $try)"
			break
		fi
	done
	[[ "$DEST" != "$MIRROR" ]] || echo "route: off LAN and the relay did not answer 3 tries, NFS mount (slow)" >&2
	rmdir "$empty"
}

# Serialize state directory mirrors; an overlapping run can skip safely.
# Through the relay the NFS mount is not needed, so its write probe (which
# stalls with the uplink) only gates the mount route.
cmd_mirror() {
	exec 9>"$STAGE/mirror-dirs.lock"
	flock -n 9 || return 0
	pick_route
	if [[ "$DEST" == "$MIRROR" ]] && ! nas_ready; then
		echo "ERROR: NAS $NAS is not mounted or not writable" >&2
		return 1
	fi
	mirror_dirs || return 1
	mark_ok
}

# mark_ok: stamp the success where the check reads it. Through the relay the
# stamps travel by rsync too, and an empty .dirs-error replaces the old one,
# since `rrsync -wo` cannot delete a single file.
mark_ok() {
	if [[ "$DEST" == "$MIRROR" ]]; then
		date +%s >"$MIRROR/.dirs-ok-at"
		rm -f "$MIRROR/.dirs-error"
		return 0
	fi
	mkdir -p "$STAGE/stamps"
	date +%s >"$STAGE/stamps/.dirs-ok-at"
	: >"$STAGE/stamps/.dirs-error"
	local try rc
	for try in 1 2 3; do
		rc=0
		timeout -k 5 120 rsync -t "${ROUTE_OPTS[@]}" "$STAGE/stamps/.dirs-ok-at" "$STAGE/stamps/.dirs-error" "$DEST/" || rc=$?
		((rc == 255)) || break
	done
	return "$rc"
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
			problems+=("briefs and Gordon state last mirrored $(((now - dirs_at) / 60)) min ago: $([[ -s "$MIRROR/.dirs-error" ]] && cat "$MIRROR/.dirs-error" || echo 'no error recorded')")
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
