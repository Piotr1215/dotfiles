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
	export CRON_STATE_DIR="$T/cron"
	export RESTIC_REPOSITORY="$T/repo" RESTIC_PASSWORD=test
	unset RESTIC_PASSWORD_FILE
	M="$T/nas/taskwarrior-mirror"
	mkdir -p "$HOME" "$T/task" "$T/nas" "$T/briefs" "$T/gordon/cases" "$T/stubs" "$T/cron"
	echo brief >"$T/briefs/b1.md"
	echo case >"$T/gordon/cases/c1.json"
	for c in mountpoint curl notify-send; do
		printf '#!/usr/bin/env bash\necho "%s $*" >>"%s/calls"\n' "$c" "$T" >"$T/stubs/$c"
		chmod +x "$T/stubs/$c"
	done
	export PATH="$T/stubs:$PATH"
	make_tasks "$TASK_DB" 40
	fake_sync "$(date '+%F %T')"
}

# A real wrapper end line, without including job output in the freshness signal.
fake_sync() {
	printf '[%s] [INFO] run end: exit=0 state=no-hit duration=1s\n' "$1" >"$CRON_STATE_DIR/__task_sync.log"
}

make_tasks() { : >"$1"; }

@test "mirror copies state directories without copying the task database" {
	run bash "$SCRIPT" mirror
	[ "$status" -eq 0 ]
	[ ! -e "$M/taskchampion.sqlite3" ]
	[ ! -e "$M/.ok-at" ]
	[ -s "$M/.dirs-ok-at" ]
	[ "$(cat "$M/state$T/briefs/b1.md")" = brief ]
	[ -f "$M/state$T/gordon/cases/c1.json" ]
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

@test "check is quiet while sync, state mirror and snapshots are current" {
	bash "$SCRIPT" mirror
	fake_restic "$(date -Iseconds)"
	run bash "$SCRIPT" check
	[ "$status" -eq 0 ]
	[[ "$output" == ok:* ]]
	! grep -q '^curl' "$T/calls"
}

@test "check pages once for stale sync and a day-old snapshot, then once on recovery" {
	bash "$SCRIPT" mirror
	fake_sync "$(date -d '-20 minutes' '+%F %T')"
	fake_restic "$(date -Iseconds -d '-30 hours')"
	run bash "$SCRIPT" check
	[ "$status" -eq 2 ]
	[[ "$output" == *"TaskChampion sync last succeeded 20 min ago"* ]]
	[[ "$output" == *"task DB is 30 h old"* ]]
	run bash "$SCRIPT" check
	[ "$status" -eq 2 ]
	[ "$(grep -c '^curl' "$T/calls")" = 1 ]
	bash "$SCRIPT" mirror
	fake_sync "$(date '+%F %T')"
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
	rm "$CRON_STATE_DIR/__task_sync.log"
	fake_restic "$(date -Iseconds -d '-12 hours')"
	TASK_BACKUP_UPTIME=60 run bash "$SCRIPT" check
	[ "$status" -eq 0 ]
}

@test "a new kind of problem pages at once, inside the re-page window" {
	bash "$SCRIPT" mirror
	fake_sync "$(date -d '-20 minutes' '+%F %T')"
	fake_restic "$(date -Iseconds)"
	run bash "$SCRIPT" check
	[ "$status" -eq 2 ]
	[ "$(grep -c '^curl' "$T/calls")" = 1 ]
	fake_restic "$(date -Iseconds -d '-30 hours')"
	run bash "$SCRIPT" check
	[ "$status" -eq 2 ]
	[ "$(grep -c '^curl' "$T/calls")" = 2 ]
}

@test "failed sync after a success does not refresh the success timestamp or expose output" {
	bash "$SCRIPT" mirror
	fake_sync "$(date -d '-20 minutes' '+%F %T')"
	printf '[%s] [ERROR] run end: exit=1 state=error duration=1s\n    secret-marker\n' "$(date '+%F %T')" >>"$CRON_STATE_DIR/__task_sync.log"
	fake_restic "$(date -Iseconds)"
	run bash "$SCRIPT" check
	[ "$status" -eq 2 ]
	[[ "$output" == *"TaskChampion sync last succeeded 20 min ago"* ]]
	[[ "$output" != *secret-marker* ]]
	! grep -q secret-marker "$T/calls"
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
