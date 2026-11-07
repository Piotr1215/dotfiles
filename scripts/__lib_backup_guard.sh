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
rsync_deletions() {
	{ "$@" --dry-run --itemize-changes 2>/dev/null || true; } | grep -c '^\*deleting' || true
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
