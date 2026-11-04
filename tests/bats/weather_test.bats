#!/usr/bin/env bats
#
# Covers the weather zsh function in .zsh_functions. curl is stubbed to print
# its arguments, so the test checks the URL built, never wttr.in.

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$STUB_BIN"
	cat >"$STUB_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@"
EOF
	chmod +x "$STUB_BIN/curl"
	# Only the weather definition, not the whole file.
	sed -n '/^function weather() {/,/^}/p' "$REPO_ROOT/.zsh_functions" >"$BATS_TEST_TMPDIR/weather.zsh"
}

run_weather() {
	run env PATH="$STUB_BIN:$PATH" CITY=Mittelbuchen zsh -f -c 'source "$1"; shift; weather "$@"' \
		test "$BATS_TEST_TMPDIR/weather.zsh" "$@"
}

@test "weather with no argument uses CITY" {
	run_weather
	[ "$status" -eq 0 ]
	[ "$output" = "wttr.in/Mittelbuchen" ]
}

@test "weather with a city uses that city over CITY" {
	run_weather Amsterdam
	[ "$status" -eq 0 ]
	[ "$output" = "wttr.in/Amsterdam" ]
}

@test "weather has no alias left to shadow the function" {
	run rg -n '^alias weather=' "$REPO_ROOT/.zsh_aliases"
	[ "$status" -eq 1 ]
}
