#!/usr/bin/env bats
#
# Covers the 8ball zsh function in .zsh_functions. classif is stubbed to print
# its arguments one per line, so the test checks what 8ball asks, never the
# local model.

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$STUB_BIN"
	cat >"$STUB_BIN/classif" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@"
EOF
	chmod +x "$STUB_BIN/classif"
	# Only the 8ball definition and its alias, not the whole file.
	sed -n '/^8ball() {/p;/^alias 8ball=/p' "$REPO_ROOT/.zsh_functions" >"$BATS_TEST_TMPDIR/8ball.zsh"
}

# The call goes on its own line: zsh applies an alias only to lines read after
# it is defined, and the noglob alias is what keeps a trailing ? from globbing.
run_8ball() {
	printf 'source %q\n8ball %s\n' "$BATS_TEST_TMPDIR/8ball.zsh" "$1" >"$BATS_TEST_TMPDIR/run.zsh"
	run env PATH="$STUB_BIN:$PATH" zsh -f "$BATS_TEST_TMPDIR/run.zsh"
}

@test "8ball forces a pick so classif never answers none" {
	run_8ball 'do you like klod?'
	[ "$status" -eq 0 ]
	[[ "$output" == *"--force"* ]]
}

@test "8ball asks the whole question as one argument" {
	run_8ball 'should I go to sleep?'
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "should I go to sleep?" ]
}
