#!/usr/bin/env bats

# Drives klaude, kapi and kcma from .zsh_claude in a bare zsh with stub pass,
# claude and python3 on PATH. The stub key is fake; no real API is called.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	ZSH_FILE="$REPO_ROOT/.zsh_claude"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	STUB_LOG="$BATS_TEST_TMPDIR/log"
	FAKE_HOME="$BATS_TEST_TMPDIR/home"
	mkdir -p "$STUB_BIN" "$STUB_LOG" "$FAKE_HOME"

	# pass: first line is the fake key, a second line must never be used.
	cat >"$STUB_BIN/pass" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$STUB_LOG/pass.args"
[ "$2" = "work/MISSING" ] && { echo "Error: $2 is not in the password store." >&2; exit 1; }
printf 'sk-fake-%s-SECRET\nsecond-line-SECRET\n' "${2#work/}"
EOF
	# claude and python3 record the key they inherit and their args, one per line.
	for stub in claude python3; do
		cat >"$STUB_BIN/$stub" <<EOF
#!/bin/sh
printf '%s\n' "\${ANTHROPIC_API_KEY-unset}" >"\$STUB_LOG/$stub.key"
printf '<%s>\n' "\$@" >"\$STUB_LOG/$stub.args"
echo "$stub ran"
echo "console: https://console.example/session" >&2
EOF
	done
	chmod +x "$STUB_BIN"/*
}

# Source .zsh_claude in zsh -f, run one command, then report the caller's state.
run_in_zsh() {
	run env -u ANTHROPIC_API_KEY HOME="$FAKE_HOME" PATH="$STUB_BIN:$PATH" STUB_LOG="$STUB_LOG" \
		zsh -f -c 'source "$1"; shift; "$@"; rc=$?
print -r -- "after=${ANTHROPIC_API_KEY-unset} key=${key-unset}"; exit $rc' zsh "$ZSH_FILE" "$@"
}

assert_no_leak() {
	[[ "$output" != *SECRET* ]]
	[[ "$output" == *"after=unset key=unset"* ]]
}

@test "klaude hands the default key to claude as ANTHROPIC_API_KEY with args intact" {
	run_in_zsh klaude -p 'hello world' '' '*' '$HOME' --model "a b"

	[ "$status" -eq 0 ]
	[ "$(cat "$STUB_LOG/pass.args")" = "show work/ANTHROPIC_SRE_AGENT_KEY" ]
	[ "$(cat "$STUB_LOG/claude.key")" = "sk-fake-ANTHROPIC_SRE_AGENT_KEY-SECRET" ]
	[ "$(cat "$STUB_LOG/claude.args")" = "$(printf '<%s>\n' -p 'hello world' '' '*' '$HOME' --model 'a b')" ]
	assert_no_leak
}

@test "klaude -k NAME reads work/NAME and drops -k from claude's args" {
	run_in_zsh klaude -k CLAUDE_API_QA_KEY --resume abc

	[ "$status" -eq 0 ]
	[ "$(cat "$STUB_LOG/pass.args")" = "show work/CLAUDE_API_QA_KEY" ]
	[ "$(cat "$STUB_LOG/claude.key")" = "sk-fake-CLAUDE_API_QA_KEY-SECRET" ]
	[ "$(cat "$STUB_LOG/claude.args")" = "$(printf '<%s>\n' --resume abc)" ]
	assert_no_leak
}

@test "klaude refuses to start claude when pass has no key" {
	run_in_zsh klaude -k MISSING

	[ "$status" -eq 1 ]
	[ ! -e "$STUB_LOG/claude.args" ]
	[[ "$output" == *"klaude: no key in pass work/MISSING"* ]]
}

@test "klaude -k with no NAME prints usage" {
	run_in_zsh klaude -k

	[ "$status" -eq 1 ]
	[ ! -e "$STUB_LOG/pass.args" ]
	[[ "$output" == *"usage: klaude"* ]]
}

@test "kapi passes the default pass entry and args to the API runner" {
	run_in_zsh kapi --model claude-opus-5-5 --prompt-file 'my prompt.txt'

	[ "$status" -eq 0 ]
	[ ! -e "$STUB_LOG/pass.args" ]
	[ "$(cat "$STUB_LOG/python3.key")" = "unset" ]
	[ "$(cat "$STUB_LOG/python3.args")" = "$(printf '<%s>\n' "$FAKE_HOME/.claude/scripts/__claude_api_run.py" \
		--pass work/ANTHROPIC_SRE_AGENT_KEY --model claude-opus-5-5 --prompt-file 'my prompt.txt')" ]
	assert_no_leak
}

@test "kcma -k NAME picks work/NAME and leaves the console URL visible" {
	run_in_zsh kcma -k ANTHROPIC_PR_REVIEW_SWARM_KEY --name probe --out 'out file.md'

	[ "$status" -eq 0 ]
	[ "$(cat "$STUB_LOG/python3.key")" = "unset" ]
	[ "$(cat "$STUB_LOG/python3.args")" = "$(printf '<%s>\n' "$FAKE_HOME/.claude/scripts/__cma_adhoc.py" \
		--pass work/ANTHROPIC_PR_REVIEW_SWARM_KEY --name probe --out 'out file.md')" ]
	[[ "$output" == *"console: https://console.example/session"* ]]
	assert_no_leak
}
