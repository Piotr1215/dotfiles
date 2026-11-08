#!/usr/bin/env bash
# Guards for __backup.sh. They live here, outside the git-crypt file, so the
# bats suite can test them (tests/bats/backup_guard_test.bats).
#
# WHY: on 2026-11-07 an agent test ran `rm -rf ~` and emptied ~/dev. The nightly
# run mirrors ~/dev and ~/loft with rsync --delete, so a run before the restore
# finished would have erased the only pre-wipe copy on the NAS. The same night
# showed the Taskwarrior DB had reached no backup since 8 Feb 2026: f942924d
# added `--filter='dir-merge,- .gitignore'`, and ~/.task/.gitignore lists
# taskchampion.sqlite3*. Repo-level .envrc files were never backed up at all.

# backup_hold_reason: while a hold file exists, print its text and succeed.
# Whoever confirms a restore is complete removes the file.
backup_hold_reason() {
	local hold="${BACKUP_HOLD_FILE:-$HOME/.local/state/backup-hold}"
	[[ -e "$hold" ]] || return 1
	cat "$hold" 2>/dev/null || true
	return 0
}

# rsync_deletions <rsync command line...>: run the command (rsync, or sudo
# rsync) as a dry run and print how many entries its --delete would remove from
# the destination. rsync parses options after its operands, so the dry-run flags
# go last. Counting entries does not work here: on 2026-11-07 a half-restored
# ~/dev had 254 top-level entries against the mirror's 253, with 72 repos empty.
# Only files and symlinks count; directory lines end in "/". The dry run lists a
# directory as deleted even when an excluded file inside keeps it ("cannot
# delete non-empty directory"), and the real run then removes nothing. On
# 2026-11-08 4,111 such directories (old __pycache__, node_modules, .git) and 2
# files made the guard refuse the dev mirror every night. A directory that holds
# real data brings its files into the count.
rsync_deletions() {
	{ "$@" --dry-run --itemize-changes 2>/dev/null || true; } | grep -c '^\*deleting .*[^/]$' || true
}

# alert_due <state file> <text>: succeed, and record <text>, when it differs
# from the last alert recorded there or that alert is a day old. A failed run
# is retried on the next hourly tick, and the same failure must not mail every
# hour until someone fixes it.
alert_due() {
	local state="$1" text="$2" key last_key="" last_ts=0 now
	key=$(printf '%s' "$text" | sha256sum | cut -c1-16)
	now=$(date +%s)
	if [[ -f "$state" ]]; then
		read -r last_key last_ts <"$state" || true
		[[ "$last_ts" =~ ^[0-9]+$ ]] || last_ts=0
		if [[ "$key" == "$last_key" ]] && ((now - last_ts < 86400)); then
			return 1
		fi
	fi
	mkdir -p "$(dirname "$state")"
	printf '%s %s\n' "$key" "$now" >"$state"
}

# sqlite_snapshot <db> <out>: consistent copy of a live SQLite database through
# the backup API (a plain copy of a WAL database can be torn), checked with
# PRAGMA integrity_check, then moved into place. Prints the row count of the
# table named in SNAPSHOT_COUNT_TABLE when set. Fails and leaves <out> alone on
# any error.
sqlite_snapshot() {
	python3 -I - "$1" "$2" "${SNAPSHOT_COUNT_TABLE:-}" <<'PY'
import os
import sqlite3
import sys

src, out, table = sys.argv[1], sys.argv[2], sys.argv[3]
if not os.path.isfile(src):
    sys.exit(f"no database at {src}")
tmp = out + ".tmp"
try:
    s = sqlite3.connect(src)
    d = sqlite3.connect(tmp)
    s.backup(d)
    s.close()
    ok = d.execute("PRAGMA integrity_check").fetchone()[0]
    rows = d.execute(f'SELECT count(*) FROM "{table}"').fetchone()[0] if table else None
    d.close()
except sqlite3.Error as e:
    if os.path.exists(tmp):
        os.unlink(tmp)
    sys.exit(f"sqlite: {e}")
if ok != "ok":
    os.unlink(tmp)
    sys.exit(f"integrity_check: {ok}")
os.replace(tmp, out)
if rows is not None:
    print(rows)
PY
}

# local_state_files <root>...: print, NUL-separated, the gitignored local state
# that no rsync rule carries: .envrc, .env, kubeconfig files and Claude
# settings.local.json, down to four levels, skipping worktrees and vendored trees.
# Files directly in a root (~/dev/.envrc) are left out: __backup.sh lists them.
# The depth test is -path, not -mindepth: -mindepth 2 also skips -prune at depth
# 1, which let ~/dev/x-worktrees through.
local_state_files() {
	local root
	for root in "$@"; do
		find "$root" -maxdepth 4 \
			\( -name node_modules -o -name .git -o -name venv -o -name .venv -o -name '*worktree*' \) -prune -o \
			-type f -path "$root/*/*" \
			\( -name .envrc -o -name .env -o -name 'kubeconfig*' -o -path '*/.claude/settings.local.json' \) \
			-print0 2>/dev/null
	done
}

# Browser profiles. 6d50d64 (14 Sep) dropped them because the nightly tar.gz
# rewrote ~975 MB; restic uploads only changed chunks. On 2026-11-07 that gap
# cost LibreWolf two months. These are re-downloadable and stay out: caches,
# site file systems (Chrome's alone was 1.6 GB), extension code, DRM plugins.
# restic matches a slash-free pattern against any path component.
# shellcheck disable=SC2034 # read by __backup.sh and the tests
BROWSER_EXCLUDES=(
	--exclude=Cache --exclude='Code Cache' --exclude=GPUCache
	--exclude=DawnGraphiteCache --exclude=DawnWebGPUCache
	--exclude='Service Worker/CacheStorage' --exclude='Service Worker/ScriptCache'
	--exclude='File System' --exclude=Extensions --exclude='Shared Dictionary'
	--exclude=cache2 --exclude=startupCache --exclude=crashes --exclude=datareporting
	--exclude=minidumps --exclude=gmp-widevinecdm --exclude='storage/default/*/cache'
)

# agent_home_excludes <home>: set restic exclusions for disposable agent data.
agent_home_excludes() {
	local home_dir="$1" dir name
	AGENT_HOME_EXCLUDES=()
	for dir in .codex .codex-work; do
		for name in cache log logs tmp .tmp .pytest_cache .ruff_cache plugins/cache shell_snapshots; do
			AGENT_HOME_EXCLUDES+=("--exclude=$home_dir/$dir/$name")
		done
		AGENT_HOME_EXCLUDES+=("--exclude=$home_dir/$dir/**/__pycache__")
	done
	for name in cache paste-cache shell-snapshots .pytest_cache .ruff_cache plugins/cache; do
		AGENT_HOME_EXCLUDES+=("--exclude=$home_dir/.claude-work/$name")
	done
	AGENT_HOME_EXCLUDES+=("--exclude=$home_dir/.claude-work/**/__pycache__")
}

# sqlite_tree_snapshot <out_root> <dir>...: checked copies of the SQLite files a
# running browser holds open, at <out_root><absolute path>. Each file is copied
# with its -wal or -journal, read through the backup API (which folds the WAL
# in), and kept only if integrity_check passes; a failed copy is retried once.
# Looks two levels down and skips cache and site-storage dirs. Prints
# "ok N failed M" and fails when any copy failed.
sqlite_tree_snapshot() {
	python3 -I - "$@" <<'PY'
import os
import shutil
import sqlite3
import sys
import tempfile

out_root, roots = sys.argv[1], sys.argv[2:]
SKIP = {"Cache", "Code Cache", "GPUCache", "Service Worker", "File System", "IndexedDB",
        "Extensions", "extensions", "Shared Dictionary", "storage", "cache2", "startupCache",
        "crashes", "datareporting", "minidumps", "gmp-widevinecdm", "security_state"}
MAGIC = b"SQLite format 3\x00"


def databases(root):
    for dirpath, dirnames, filenames in os.walk(root):
        depth = os.path.relpath(dirpath, root).count(os.sep) + (dirpath != root)
        dirnames[:] = [d for d in dirnames if d not in SKIP and depth < 1]
        for name in filenames:
            path = os.path.join(dirpath, name)
            try:
                if os.path.islink(path) or os.path.getsize(path) > 512 << 20:
                    continue
                with open(path, "rb") as fh:
                    if fh.read(16) == MAGIC:
                        yield path
            except OSError:
                continue


def snap(path, out):
    os.makedirs(os.path.dirname(out), exist_ok=True)
    tmp = out + ".tmp"
    for _ in range(2):
        with tempfile.TemporaryDirectory() as td:
            base = os.path.join(td, "db")
            try:
                shutil.copyfile(path, base)
                for suffix in ("-wal", "-journal"):
                    if os.path.exists(path + suffix):
                        shutil.copyfile(path + suffix, base + suffix)
                s = sqlite3.connect(base)
                d = sqlite3.connect(tmp)
                s.backup(d)
                s.close()
                ok = d.execute("PRAGMA integrity_check").fetchone()[0]
                d.close()
            except (OSError, sqlite3.Error) as e:
                ok = str(e)
        if ok == "ok":
            os.replace(tmp, out)
            return True
        if os.path.exists(tmp):
            os.unlink(tmp)
    print(f"failed: {path}: {ok}", file=sys.stderr)
    return False


good = bad = 0
for root in roots:
    if not os.path.isdir(root):
        continue
    for path in databases(root):
        if snap(path, out_root + os.path.abspath(path)):
            good += 1
        else:
            bad += 1
print(f"ok {good} failed {bad}")
sys.exit(1 if bad else 0)
PY
}
