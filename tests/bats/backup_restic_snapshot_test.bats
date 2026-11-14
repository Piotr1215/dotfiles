#!/usr/bin/env bats
# Tests for restic_snapshot in scripts/__backup.sh: restic exit 3 caused only by
# files that vanished mid-scan is a warning, anything else stays a failure.
# The function is lifted out of the script and run against a stub restic.

SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__backup.sh"

setup() {
	mkdir -p "$BATS_TEST_TMPDIR/bin"
	export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
	eval "$(sed -n '/^restic_snapshot() {/,/^}/p' "$SCRIPT")"
	FAILED=()
	LOGGED=""
	log() { LOGGED+="[$1] $2"$'\n'; }
	record_failure() { FAILED+=("$1"); log ERROR "$1"; }
}

# Stub restic: prints the given stderr lines and exits with the given code.
stub_restic() {
	local rc="$1"
	shift
	{
		printf '#!/usr/bin/env bash\n'
		printf 'printf "snapshot abc saved\\n"\n'
		for line in "$@"; do printf 'printf "%%s\\n" %q >&2\n' "$line"; done
		printf 'exit %s\n' "$rc"
	} >"$BATS_TEST_TMPDIR/bin/restic"
	chmod +x "$BATS_TEST_TMPDIR/bin/restic"
}

@test "a clean snapshot records no failure" {
	stub_restic 0
	restic_snapshot "restic home" --tag home /x
	[ "${#FAILED[@]}" -eq 0 ]
}

@test "exit 3 with only vanished files is a warning, not a failure" {
	stub_restic 3 \
		'error: lstat /h/.local/state/wip-capture/out.Yb8ZLzwm: no such file or directory' \
		'error: lstat /h/.task/taskchampion.sqlite3-wal: no such file or directory' \
		'Warning: at least one source file could not be read'
	restic_snapshot "restic home" --tag home /x
	[ "${#FAILED[@]}" -eq 0 ]
	[[ "$LOGGED" == *'[WARNING] restic home: snapshot saved; 2 file(s) vanished during the scan'* ]]
}

@test "exit 3 with a permission error still fails" {
	stub_restic 3 \
		'error: lstat /h/.task/taskchampion.sqlite3-wal: no such file or directory' \
		'error: open /h/secret: permission denied' \
		'Warning: at least one source file could not be read'
	run restic_snapshot "restic home" --tag home /x
	[ "$status" -eq 1 ]
	[[ "$output" == *'permission denied'* ]]
}

@test "exit 3 with no error lines still fails" {
	stub_restic 3 'Warning: at least one source file could not be read'
	run restic_snapshot "restic home" --tag home /x
	[ "$status" -eq 1 ]
}

@test "any other non-zero exit fails and is recorded" {
	stub_restic 1 'Fatal: unable to open repository'
	restic_snapshot "restic Downloads" --tag downloads /x || true
	[ "${FAILED[0]}" = "restic Downloads" ]
}

@test "restic stderr is passed through for the log" {
	stub_restic 0 'some note'
	run restic_snapshot "restic home" /x
	[[ "$output" == *'some note'* ]]
}
