#!/usr/bin/env bats
# Tests for scripts/__lib_backup_guard.sh and the hold in scripts/__backup.sh.
# Everything runs in BATS_TEST_TMPDIR. The one __backup.sh run has mountpoint,
# rsync, restic and sudo stubbed first on PATH, and the mountpoint stub reports
# the NAS as unmounted, so even a broken hold stops before any copy.

LIB="${BATS_TEST_DIRNAME}/../../scripts/__lib_backup_guard.sh"
BACKUP="${BATS_TEST_DIRNAME}/../../scripts/__backup.sh"

setup() {
	# shellcheck source=../../scripts/__lib_backup_guard.sh
	source "$LIB"
	T="$BATS_TEST_TMPDIR"
	export HOME="$T/home"
	mkdir -p "$HOME"
}

@test "no hold file means no hold" {
	BACKUP_HOLD_FILE="$T/none" run backup_hold_reason
	[ "$status" -eq 1 ]
}

@test "a hold file holds and prints its reason" {
	echo "restore in progress" >"$T/hold"
	BACKUP_HOLD_FILE="$T/hold" run backup_hold_reason
	[ "$status" -eq 0 ]
	[ "$output" = "restore in progress" ]
}

@test "rsync_deletions counts what --delete would remove and removes nothing" {
	mkdir -p "$T/src" "$T/dst/gone"
	touch "$T/src/a" "$T/dst/a" "$T/dst/x1" "$T/dst/x2" "$T/dst/gone/f"
	run rsync_deletions rsync -a --delete "$T/src/" "$T/dst/"
	[ "$status" -eq 0 ]
	[ "$output" = "4" ]
	[ -e "$T/dst/x1" ] && [ -e "$T/dst/gone/f" ]
}

@test "rsync_deletions is 0 for a mirror that matches" {
	mkdir -p "$T/src" "$T/dst"
	touch "$T/src/a" "$T/dst/a"
	run rsync_deletions rsync -a --delete "$T/src/" "$T/dst/"
	[ "$status" -eq 0 ]
	[ "$output" = "0" ]
}

@test "rsync_deletions prints 0, not an error, when the dry run fails" {
	run rsync_deletions rsync -a --delete "$T/absent/" "$T/dst/"
	[ "$status" -eq 0 ]
	[ "$output" = "0" ]
}

@test "sqlite snapshot carries rows still in the WAL" {
	db="$T/live.sqlite3"
	# A writer holds the database open in WAL mode with no checkpoint, so the
	# last row lives only in the -wal file, as with a running Taskwarrior.
	python3 -I - "$db" "$T/ready" "$T/release" <<'PY' &
import os, sqlite3, sys, time
db, ready, release = sys.argv[1:]
c = sqlite3.connect(db)
c.execute("PRAGMA journal_mode=WAL")
c.execute("PRAGMA wal_autocheckpoint=0")
c.execute("CREATE TABLE tasks (uuid TEXT)")
c.executemany("INSERT INTO tasks VALUES (?)", [(str(i),) for i in range(3)])
c.commit()
open(ready, "w").close()
for _ in range(100):
    if os.path.exists(release):
        break
    time.sleep(0.1)
PY
	writer=$!
	for _ in $(seq 50); do [ -e "$T/ready" ] && break; sleep 0.1; done
	[ -s "$db-wal" ]
	SNAPSHOT_COUNT_TABLE=tasks run sqlite_snapshot "$db" "$T/snap.sqlite3"
	touch "$T/release"
	wait "$writer"
	[ "$status" -eq 0 ]
	[ "$output" = "3" ]
	[ ! -e "$T/snap.sqlite3.tmp" ]
}

@test "a failed snapshot leaves the previous one in place" {
	echo previous >"$T/snap.sqlite3"
	run sqlite_snapshot "$T/absent.sqlite3" "$T/snap.sqlite3"
	[ "$status" -ne 0 ]
	echo "not a database" >"$T/junk.sqlite3"
	run sqlite_snapshot "$T/junk.sqlite3" "$T/snap.sqlite3"
	[ "$status" -ne 0 ]
	[ "$(cat "$T/snap.sqlite3")" = previous ]
	[ ! -e "$T/snap.sqlite3.tmp" ]
}

@test "local state files: repo secrets and local settings, not vendored or nested copies" {
	r="$T/dev"
	mkdir -p "$r/homelab/.claude" "$r/app/node_modules/x" "$r/x-worktrees/a" "$r/a/b/c/d/e"
	touch "$r/.envrc" "$r/homelab/.envrc" "$r/homelab/kubeconfig" "$r/homelab/.claude/settings.local.json" \
		"$r/homelab/.env" "$r/app/node_modules/x/.env" "$r/x-worktrees/a/.envrc" "$r/a/b/c/d/e/.envrc" \
		"$r/homelab/settings.local.json"
	run bash -c "source '$LIB'; local_state_files '$r' | tr '\0' '\n' | sort"
	[ "$status" -eq 0 ]
	[ "$output" = "$(printf '%s\n' "$r/homelab/.claude/settings.local.json" "$r/homelab/.env" "$r/homelab/.envrc" "$r/homelab/kubeconfig")" ]
}

@test "__backup.sh on hold exits 0 and runs nothing" {
	stubs="$T/stubs"
	mkdir -p "$stubs"
	for c in mountpoint rsync restic sudo; do
		printf '#!/usr/bin/env bash\necho "%s $*" >>"%s/calls"\nexit 1\n' "$c" "$T" >"$stubs/$c"
		chmod +x "$stubs/$c"
	done
	echo "restore running" >"$T/hold"
	PATH="$stubs:$PATH" BACKUP_HOLD_FILE="$T/hold" run bash "$BACKUP"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Backup held, nothing run: restore running"* ]]
	[ ! -e "$T/calls" ]
}

# make_db <path> <rows> [wal]: a SQLite file with <rows> rows in table t.
make_db() {
	python3 -I - "$@" <<'PY'
import sqlite3, sys
path, rows = sys.argv[1], int(sys.argv[2])
c = sqlite3.connect(path)
if len(sys.argv) > 3:
    c.execute("PRAGMA journal_mode=WAL")
c.execute("CREATE TABLE t (v)")
c.executemany("INSERT INTO t VALUES (?)", [(i,) for i in range(rows)])
c.commit()
PY
}

@test "browser DB copies: open WAL and journal DBs copied, caches, deep files and non-DBs skipped" {
	p="$T/profile"
	mkdir -p "$p/Network" "$p/Cache" "$p/a/b"
	make_db "$p/Network/Cookies" 2
	make_db "$p/Cache/index" 1
	make_db "$p/a/b/deep.sqlite" 1
	echo '{}' >"$p/Preferences"
	# places.sqlite stays open with its last rows only in the -wal file.
	python3 -I - "$p/places.sqlite" "$T/ready" "$T/release" <<'PY' &
import os, sqlite3, sys, time
db, ready, release = sys.argv[1:]
c = sqlite3.connect(db)
c.execute("PRAGMA journal_mode=WAL")
c.execute("PRAGMA wal_autocheckpoint=0")
c.execute("CREATE TABLE t (v)")
c.executemany("INSERT INTO t VALUES (?)", [(i,) for i in range(5)])
c.commit()
open(ready, "w").close()
for _ in range(100):
    if os.path.exists(release):
        break
    time.sleep(0.1)
PY
	writer=$!
	for _ in $(seq 50); do [ -e "$T/ready" ] && break; sleep 0.1; done
	run sqlite_tree_snapshot "$T/out" "$p"
	touch "$T/release"
	wait "$writer"
	[ "$status" -eq 0 ]
	[ "$output" = "ok 2 failed 0" ]
	[ "$(python3 -I -c 'import sqlite3,sys;print(sqlite3.connect(sys.argv[1]).execute("select count(*) from t").fetchone()[0])' "$T/out$p/places.sqlite")" = 5 ]
	[ -f "$T/out$p/Network/Cookies" ]
	[ ! -e "$T/out$p/Cache/index" ] && [ ! -e "$T/out$p/a/b/deep.sqlite" ] && [ ! -e "$T/out$p/Preferences" ]
}

@test "browser DB copies: a damaged DB is reported and not copied" {
	p="$T/profile"
	mkdir -p "$p"
	make_db "$p/good.sqlite" 1
	{ printf 'SQLite format 3\000'; head -c 8192 /dev/urandom; } >"$p/bad.sqlite"
	run sqlite_tree_snapshot "$T/out" "$p"
	[ "$status" -eq 1 ]
	[[ "$output" == *"failed: $p/bad.sqlite"* ]]
	[[ "$output" == *"ok 1 failed 1"* ]]
	[ ! -e "$T/out$p/bad.sqlite" ] && [ ! -e "$T/out$p/bad.sqlite.tmp" ]
}

@test "browser excludes keep profile data and drop caches in restic" {
	command -v restic >/dev/null || skip "restic not installed"
	p="$T/browser"
	for d in "Default/Cache" "Default/Code Cache" "Default/Service Worker/CacheStorage" \
		"Default/Service Worker/Database" "Default/File System" "Default/Extensions" "Default/IndexedDB" \
		"prof/cache2" "prof/storage/default/https+++x/cache" "prof/storage/default/https+++x/idb" "prof/extensions"; do
		mkdir -p "$p/$d" && echo x >"$p/$d/f"
	done
	echo x >"$p/Default/History"
	echo x >"$p/prof/places.sqlite"
	export RESTIC_REPOSITORY="$T/repo" RESTIC_PASSWORD=test RESTIC_CACHE_DIR="$T/cache"
	restic init -q
	restic backup -q "${BROWSER_EXCLUDES[@]}" "$p"
	run restic ls -q latest
	for kept in Default/History "Default/Service Worker/Database/f" Default/IndexedDB/f prof/places.sqlite \
		prof/storage/default/https+++x/idb/f prof/extensions/f; do
		[[ "$output" == *"$p/$kept"* ]] || { echo "missing $kept"; false; }
	done
	for dropped in Default/Cache "Default/Code Cache" "Default/Service Worker/CacheStorage" "Default/File System" \
		Default/Extensions prof/cache2 prof/storage/default/https+++x/cache; do
		[[ "$output" != *"$p/$dropped"* ]] || { echo "kept $dropped"; false; }
	done
}
