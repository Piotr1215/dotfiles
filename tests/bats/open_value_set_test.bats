#!/usr/bin/env bats
#
# Covers the "open" value-set behind ;;open, the rofi twin of M-x: zoxide folders
# first, then files changed in the last 30 days newest first (the M-x Ctrl+F
# list). Each row types the absolute path and shows it with ~ for $HOME.

setup() {
	SET="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/.config/value-sets/open"
	export HOME="$BATS_TEST_TMPDIR/home"
	ROOT="$HOME/dev"
	mkdir -p "$ROOT/repo/.git" "$ROOT/repo/node_modules" "$ROOT/repo-worktrees/wt" "$BATS_TEST_TMPDIR/bin"
	export VALUE_SET_ROOTS="$ROOT"
	export VALUE_SET_CACHE="$BATS_TEST_TMPDIR/cache/open"

	# zoxide stub: the frecency list of folders, as `zoxide query -l` prints it.
	cat > "$BATS_TEST_TMPDIR/bin/zoxide" <<-STUB
		#!/usr/bin/env bash
		[ "\$*" = "query -l" ] && printf '%s\n' "$HOME/dev/repo" "$HOME/notes"
	STUB
	chmod +x "$BATS_TEST_TMPDIR/bin/zoxide"
	export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

row() { printf '%s\t%s' "$1" "$2"; }

@test "folders come first, labelled with ~ and a trailing slash" {
	run "$SET"
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "$(row "$HOME/dev/repo" "~/dev/repo/")" ]
	[ "${lines[1]}" = "$(row "$HOME/notes" "~/notes/")" ]
}

@test "files follow, newest first, typed as absolute paths" {
	touch -d '3 days ago' "$ROOT/repo/old.md"
	touch -d '1 hour ago' "$ROOT/repo/new.sh"
	run "$SET"
	[ "$status" -eq 0 ]
	[ "${lines[2]}" = "$(row "$ROOT/repo/new.sh" "~/dev/repo/new.sh")" ]
	[ "${lines[3]}" = "$(row "$ROOT/repo/old.md" "~/dev/repo/old.md")" ]
	[ "${#lines[@]}" -eq 4 ]
}

@test "files older than 30 days are left out" {
	touch -d '40 days ago' "$ROOT/repo/stale.txt"
	run "$SET"
	[ "$status" -eq 0 ]
	! printf '%s\n' "$output" | grep -q stale.txt
}

@test "skips .git, node_modules and agent worktrees, keeps hidden files" {
	touch "$ROOT/repo/.git/HEAD" "$ROOT/repo/node_modules/x.js" "$ROOT/repo-worktrees/wt/y.sh" "$ROOT/repo/.envrc"
	run "$SET"
	[ "$status" -eq 0 ]
	! printf '%s\n' "$output" | grep -qE 'HEAD|x\.js|y\.sh'
	printf '%s\n' "$output" | grep -qxF "$(row "$ROOT/repo/.envrc" "~/dev/repo/.envrc")"
}

@test "a missing root or a failing zoxide still lists the rest" {
	touch "$ROOT/repo/kept.md"
	printf '#!/usr/bin/env bash\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/zoxide"
	VALUE_SET_ROOTS="$ROOT $HOME/absent" run "$SET"
	[ "$status" -eq 0 ]
	[ "$output" = "$(row "$ROOT/repo/kept.md" "~/dev/repo/kept.md")" ]
}

@test "the file scan is cached, and a fresh cache is served without scanning" {
	touch "$ROOT/repo/first.md"
	run "$SET"
	[ "$status" -eq 0 ]
	grep -qF "$ROOT/repo/first.md" "$VALUE_SET_CACHE"
	touch "$ROOT/repo/later.md"
	run "$SET"
	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | grep -qF "$ROOT/repo/first.md"
	! printf '%s\n' "$output" | grep -qF later.md
}

@test "a stale cache is served at once, then refreshed in the background" {
	touch "$ROOT/repo/real.md"
	mkdir -p "$(dirname "$VALUE_SET_CACHE")"
	printf '/old/row\t~old\n' > "$VALUE_SET_CACHE"
	touch -d '2 minutes ago' "$VALUE_SET_CACHE"
	run "$SET"
	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | grep -qxF "$(row /old/row "~old")"
	for _ in $(seq 50); do grep -qF real.md "$VALUE_SET_CACHE" && break; sleep 0.1; done
	grep -qF "$ROOT/repo/real.md" "$VALUE_SET_CACHE"
	! grep -qF /old/row "$VALUE_SET_CACHE"
}
