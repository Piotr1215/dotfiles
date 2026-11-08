#!/usr/bin/env bash
# Continuous NAS mirror of the Taskwarrior DB, the handoff briefs and Gordon
# state, and the alert that says when any task backup goes stale.
#
# WHY: on 2026-11-07 an agent test ran `rm -rf ~`. The task DB had reached no
# backup since 8 Feb (a .gitignore filter in the nightly rsync), so the newest
# copy anywhere was from 13 Oct. Piotr, 8 Nov: "let's make damn sure this is
# continuously mirrored to nas"; with the mirror in place, "every 15 min is way
# too aggressive", "these should be daily snapshot".
#
# Two layers:
#   mirror    this script, every minute from cron. A checked copy of the DB on
#             the NAS, replaced only when it passes integrity_check and holds at
#             least half the tasks of the copy it replaces. Briefs and Gordon
#             state go over with rsync and no --delete. A missing, emptied or
#             damaged source stops the mirror; it never empties the NAS copy.
#   daily     __backup.sh at 20:00: a restic snapshot of the same three, kept
#             7 daily, 4 weekly, 6 monthly. A bad mirror run cannot reach it.
#
# `check`, every 5 minutes from cron, pages ntfy when the NAS is gone, the DB
# mirror has not succeeded for 5 minutes, the state dirs for 30, or the newest
# daily snapshot is over 26 hours old. It exits 2 on an alert, the cron
# wrapper's "hit".
#
# Restore, never in place:
#   mirror: /mnt/nas-backup/taskwarrior-mirror/taskchampion.sqlite3 and state/
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
MIRROR_MAX_AGE="${TASK_MIRROR_MAX_AGE:-300}"
DIRS_MAX_AGE="${TASK_DIRS_MAX_AGE:-1800}"
# The path __backup.sh puts the daily DB copy under; it marks the snapshots.
SNAPSHOT_PATH="${TASK_SNAPSHOT_PATH:-$HOME/.local/share/task-backups}"
SNAPSHOT_MAX_AGE="${TASK_SNAPSHOT_MAX_AGE:-93600}"
REALERT_AFTER="${TASK_REALERT_AFTER:-21600}"
export RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-$NAS/secure-store}"
[[ -n "$RESTIC_PASSWORD" ]] || export RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE:-$HOME/.config/restic/password}"

# shellcheck source=./__lib_backup_guard.sh
source "$(dirname "${BASH_SOURCE[0]}")/__lib_backup_guard.sh"

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

# source_sig: mtime and size of the DB and its WAL; equal means nothing to copy.
source_sig() {
	stat -c '%.9Y %s' "$TASK_DB" "$TASK_DB-wal" 2>/dev/null | tr '\n' ' ' || true
}

# mirror_db: copy the DB to the NAS when it changed, unless the copy is damaged
# or has under half the tasks of the NAS copy (a wiped or replaced DB).
mirror_db() {
	local sig rows prev
	sig=$(source_sig)
	if [[ -f "$MIRROR/taskchampion.sqlite3" && "$sig" == "$(cat "$MIRROR/.source-sig" 2>/dev/null)" ]]; then
		return 0
	fi
	if ! rows=$(SNAPSHOT_COUNT_TABLE=tasks sqlite_snapshot "$TASK_DB" "$STAGE/mirror.sqlite3" 2>&1); then
		fail "task DB copy failed, NAS copy kept: $rows"
		return 1
	fi
	prev=$(cat "$MIRROR/.tasks" 2>/dev/null || echo 0)
	if ((prev >= 20 && rows * 2 < prev)) && [[ "$ACCEPT_SHRINK" != 1 ]]; then
		fail "task DB shrank from $prev to $rows tasks, NAS copy kept. If intended: ${0##*/} mirror --accept-shrink"
		return 1
	fi
	if ! timeout -k 5 60 cp "$STAGE/mirror.sqlite3" "$MIRROR/.taskchampion.sqlite3.tmp" ||
		! mv -f "$MIRROR/.taskchampion.sqlite3.tmp" "$MIRROR/taskchampion.sqlite3"; then
		fail "copy to $MIRROR failed"
		return 1
	fi
	echo "$rows" >"$MIRROR/.tasks"
	echo "$sig" >"$MIRROR/.source-sig"
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

# The DB and the dirs take separate locks. Walking Gordon state (12k files over
# NFS) takes 13 s idle and over a minute under load; under one lock it made the
# next runs skip, and a DB change took up to 151 s to reach the NAS.
cmd_mirror() {
	local rc=0
	if ! nas_ready; then
		echo "ERROR: NAS $NAS is not mounted or not writable" >&2
		return 1
	fi
	exec 8>"$STAGE/mirror-db.lock"
	if flock -n 8; then
		if mirror_db; then
			date +%s >"$MIRROR/.ok-at"
			rm -f "$MIRROR/.last-error"
		else
			rc=1
		fi
		flock -u 8
	fi
	exec 9>"$STAGE/mirror-dirs.lock"
	flock -n 9 || return "$rc"
	if mirror_dirs; then
		date +%s >"$MIRROR/.dirs-ok-at"
		rm -f "$MIRROR/.dirs-error"
	else
		rc=1
	fi
	return "$rc"
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
	local problems=() kinds=() now up ok_at dirs_at snap msg alerted="$STAGE/alerted"
	now=$(date +%s)
	up=${TASK_BACKUP_UPTIME:-$(cut -d. -f1 /proc/uptime)}
	[[ -f "$TASK_DB" ]] || { problems+=("no task DB at $TASK_DB"); kinds+=(db); }
	if ! nas_ready; then
		problems+=("NAS $NAS is not mounted or not writable")
		kinds+=(nas)
	else
		# The mirror's age counts only once cron had time to run it after boot.
		ok_at=$(cat "$MIRROR/.ok-at" 2>/dev/null || echo 0)
		if ((now - ok_at > MIRROR_MAX_AGE && up > MIRROR_MAX_AGE)); then
			problems+=("mirror last succeeded $(((now - ok_at) / 60)) min ago: $(cat "$MIRROR/.last-error" 2>/dev/null || echo 'no error recorded, is its cron job running?')")
			kinds+=(mirror)
		fi
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
		page default white_check_mark "recovered: mirror and daily snapshot are current"
		rm -f "$alerted"
	fi
	echo "ok: mirror $(((now - ok_at) / 60)) min old, daily snapshot $(((now - snap) / 3600)) h old"
}

umask 077
mkdir -p "$STAGE"
ACCEPT_SHRINK=0
case "${1:-}" in
mirror)
	[[ "${2:-}" == --accept-shrink ]] && ACCEPT_SHRINK=1
	cmd_mirror
	;;
check) cmd_check ;;
*)
	echo "usage: ${0##*/} mirror [--accept-shrink] | check" >&2
	exit 64
	;;
esac
