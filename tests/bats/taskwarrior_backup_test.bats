#!/usr/bin/env bats
# Tests for scripts/__taskwarrior_backup.sh. The NAS, the staging dir and the
# restic repo are temp dirs; mountpoint, curl and notify-send are stubs that
# log their calls. restic is real (a throwaway repo) except in the check tests.

SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__taskwarrior_backup.sh"

setup() {
	T="$BATS_TEST_TMPDIR"
	export HOME="$T/home"
	export TASK_DB="$T/task/taskchampion.sqlite3"
	export TASK_BACKUP_NAS="$T/nas"
	export TASK_BACKUP_STAGE="$T/stage"
	export TASK_BACKUP_DIRS="$T/briefs:$T/gordon"
	export TASK_BACKUP_NTFY="http://ntfy.invalid/topic"
	export TASK_BACKUP_UPTIME=100000
	export RESTIC_REPOSITORY="$T/repo" RESTIC_PASSWORD=test
	unset RESTIC_PASSWORD_FILE
	M="$T/nas/taskwarrior-mirror"
	mkdir -p "$HOME" "$T/task" "$T/nas" "$T/briefs" "$T/gordon/cases" "$T/stubs"
	echo brief >"$T/briefs/b1.md"
	echo case >"$T/gordon/cases/c1.json"
	for c in mountpoint curl notify-send; do
		printf '#!/usr/bin/env bash\necho "%s $*" >>"%s/calls"\n' "$c" "$T" >"$T/stubs/$c"
		chmod +x "$T/stubs/$c"
	done
	export PATH="$T/stubs:$PATH"
	make_tasks "$TASK_DB" 40
}

# make_tasks <db> <n>: a WAL-mode DB with n rows in a taskchampion-shaped table.
make_tasks() {
	python3 -I - "$@" <<'PY'
import sqlite3, sys, uuid
c = sqlite3.connect(sys.argv[1])
c.execute("PRAGMA journal_mode=WAL")
c.execute("CREATE TABLE IF NOT EXISTS tasks (uuid TEXT PRIMARY KEY, data TEXT)")
c.execute("DELETE FROM tasks")
c.executemany("INSERT INTO tasks VALUES (?, '{}')", [(str(uuid.uuid4()),) for _ in range(int(sys.argv[2]))])
c.commit()
PY
}

count() { python3 -I -c 'import sqlite3,sys;print(sqlite3.connect(sys.argv[1]).execute("select count(*) from tasks").fetchone()[0])' "$1"; }

@test "mirror puts a checked DB copy and the state dirs on the NAS, and the copy restores" {
	run bash "$SCRIPT" mirror
	[ "$status" -eq 0 ]
	[ "$(count "$M/taskchampion.sqlite3")" = 40 ]
	[ "$(cat "$M/.tasks")" = 40 ]
	[ -s "$M/.ok-at" ] && [ -s "$M/.dirs-ok-at" ] && [ ! -e "$M/.last-error" ]
	[ "$(cat "$M/state$T/briefs/b1.md")" = brief ]
	[ -f "$M/state$T/gordon/cases/c1.json" ]
}

@test "an unchanged DB is not copied again, but the run still counts as a success" {
	bash "$SCRIPT" mirror
	touch -d '2020-01-01' "$M/taskchampion.sqlite3"
	echo 0 >"$M/.ok-at"
	run bash "$SCRIPT" mirror
	[ "$status" -eq 0 ]
	[ "$(stat -c %Y "$M/taskchampion.sqlite3")" = "$(date -d 2020-01-01 +%s)" ]
	[ "$(cat "$M/.ok-at")" -gt 0 ]
}

@test "a DB that lost over half its tasks stops the mirror until accepted" {
	bash "$SCRIPT" mirror
	make_tasks "$TASK_DB" 3
	run bash "$SCRIPT" mirror
	[ "$status" -eq 1 ]
	[ "$(count "$M/taskchampion.sqlite3")" = 40 ]
	grep -q 'shrank from 40 to 3' "$M/.last-error"
	run bash "$SCRIPT" mirror --accept-shrink
	[ "$status" -eq 0 ]
	[ "$(count "$M/taskchampion.sqlite3")" = 3 ]
}

@test "a missing or damaged DB stops the mirror and keeps the NAS copy" {
	bash "$SCRIPT" mirror
	echo "not a database" >"$TASK_DB"
	run bash "$SCRIPT" mirror
	[ "$status" -eq 1 ]
	grep -q 'copy failed' "$M/.last-error"
	command rm -f "$TASK_DB"
	run bash "$SCRIPT" mirror
	[ "$status" -eq 1 ]
	[ "$(count "$M/taskchampion.sqlite3")" = 40 ]
}

@test "files deleted from a state dir stay on the NAS; a missing state dir stops the mirror" {
	bash "$SCRIPT" mirror
	command rm -f "$T/briefs/b1.md"
	bash "$SCRIPT" mirror
	[ -f "$M/state$T/briefs/b1.md" ]
	mv "$T/gordon" "$T/gordon.away"
	run bash "$SCRIPT" mirror
	[ "$status" -eq 1 ]
	grep -q "gordon is missing" "$M/.dirs-error"
	[ ! -e "$M/.last-error" ]
	[ -f "$M/state$T/gordon/cases/c1.json" ]
}

# fake_restic <iso time>: restic stub whose snapshot list has one at that time.
fake_restic() {
	printf '#!/usr/bin/env bash\necho %q\n' "[{\"time\":\"$1\"}]" >"$T/stubs/restic"
	chmod +x "$T/stubs/restic"
}

@test "check is quiet while the mirror and snapshots are current" {
	bash "$SCRIPT" mirror
	fake_restic "$(date -Iseconds)"
	run bash "$SCRIPT" check
	[ "$status" -eq 0 ]
	[[ "$output" == ok:* ]]
	! grep -q '^curl' "$T/calls"
}

@test "check pages once for a stale mirror and a day-old snapshot, then once on recovery" {
	bash "$SCRIPT" mirror
	echo "$(($(date +%s) - 900))" >"$M/.ok-at"
	echo "2026-11-08 00:00:00 rsync failed" >"$M/.last-error"
	fake_restic "$(date -Iseconds -d '-30 hours')"
	run bash "$SCRIPT" check
	[ "$status" -eq 2 ]
	[[ "$output" == *"mirror last succeeded 15 min ago"*"rsync failed"* ]]
	[[ "$output" == *"task DB is 30 h old"* ]]
	run bash "$SCRIPT" check
	[ "$status" -eq 2 ]
	[ "$(grep -c '^curl' "$T/calls")" = 1 ]
	bash "$SCRIPT" mirror
	fake_restic "$(date -Iseconds)"
	run bash "$SCRIPT" check
	[ "$status" -eq 0 ]
	[ "$(grep -c '^curl' "$T/calls")" = 2 ]
	grep -q 'recovered' "$T/calls"
}

@test "check pages when the NAS is not mounted" {
	printf '#!/usr/bin/env bash\nexit 1\n' >"$T/stubs/mountpoint"
	run bash "$SCRIPT" check
	[ "$status" -eq 2 ]
	[[ "$output" == *"is not mounted"* ]]
	grep -q '^curl.*Priority: high' "$T/calls"
}

@test "right after boot, old stamps do not page" {
	bash "$SCRIPT" mirror
	echo 0 >"$M/.ok-at"
	fake_restic "$(date -Iseconds -d '-12 hours')"
	TASK_BACKUP_UPTIME=60 run bash "$SCRIPT" check
	[ "$status" -eq 0 ]
}

@test "a new kind of problem pages at once, inside the re-page window" {
	bash "$SCRIPT" mirror
	echo "$(($(date +%s) - 900))" >"$M/.ok-at"
	fake_restic "$(date -Iseconds)"
	run bash "$SCRIPT" check
	[ "$status" -eq 2 ]
	[ "$(grep -c '^curl' "$T/calls")" = 1 ]
	fake_restic "$(date -Iseconds -d '-30 hours')"
	run bash "$SCRIPT" check
	[ "$status" -eq 2 ]
	[ "$(grep -c '^curl' "$T/calls")" = 2 ]
}

@test "a DB change reaches the NAS while a slow state-dir walk holds its lock" {
	bash "$SCRIPT" mirror
	make_tasks "$TASK_DB" 41
	flock "$T/stage/mirror-dirs.lock" sleep 5 &
	holder=$!
	sleep 0.5
	run bash "$SCRIPT" mirror
	kill "$holder" 2>/dev/null || true
	[ "$status" -eq 0 ]
	[ "$(count "$M/taskchampion.sqlite3")" = 41 ]
}

@test "check pages when briefs and Gordon state stop mirroring" {
	bash "$SCRIPT" mirror
	echo "$(($(date +%s) - 3600))" >"$M/.dirs-ok-at"
	echo "2026-11-08 01:00:00 rsync of /x failed (exit 23)" >"$M/.dirs-error"
	fake_restic "$(date -Iseconds)"
	run bash "$SCRIPT" check
	[ "$status" -eq 2 ]
	[[ "$output" == *"Gordon state last mirrored 60 min ago"*"exit 23"* ]]
	[[ "$output" != *"mirror last succeeded"* ]]
}
