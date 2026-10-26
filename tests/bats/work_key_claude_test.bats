#!/usr/bin/env bats

# Drives klaude, kapi and kcma from .zsh_claude in a bare zsh with stub pass,
# claude and python3 on PATH and a stub claude launcher under the fake HOME.
# The stub key is fake; no real API is called. klaude hands Claude an inline
# apiKeyHelper through --settings, so the tests run that helper the way Claude
# Code does to prove which pass entry it reads.

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
	chmod +x "$STUB_BIN/pass"
	# claude, python3 and the launcher record the key and key name they inherit
	# and their args, one per line, under the log name given as the second argument.
	mkdir -p "$FAKE_HOME/.claude/scripts"
	make_stub "$STUB_BIN/claude" claude
	make_stub "$STUB_BIN/python3" python3
	make_stub "$FAKE_HOME/.claude/scripts/__claude_with_monitor.sh" launcher
}

make_stub() {
	cat >"$1" <<EOF
#!/bin/sh
printf '%s\n' "\${ANTHROPIC_API_KEY-unset}" >"\$STUB_LOG/$2.key"
printf '%s\n' "\${KLAUDE_KEY_NAME-unset}" >"\$STUB_LOG/$2.keyname"
printf '<%s>\n' "\$@" >"\$STUB_LOG/$2.args"
echo "$2 ran"
echo "console: https://console.example/session" >&2
EOF
	chmod +x "$1"
}

# Source .zsh_claude in zsh -f, run one command, then report the caller's state.
run_in_zsh() {
	run env -u ANTHROPIC_API_KEY -u KLAUDE_KEY_NAME HOME="$FAKE_HOME" PATH="$STUB_BIN:$PATH" STUB_LOG="$STUB_LOG" \
		zsh -f -c 'source "$1"; shift; "$@"; rc=$?
print -r -- "after=${ANTHROPIC_API_KEY-unset} key=${key-unset} keyname=${KLAUDE_KEY_NAME-unset}"; exit $rc' zsh "$ZSH_FILE" "$@"
}

# The launcher's first two args must be --settings and JSON whose only key is an
# apiKeyHelper reading work/$1. Run the helper through /bin/sh, as Claude Code
# does, and check it yields that entry's first line while the launcher itself
# inherited no key, only the entry name.
assert_helper_for() {
	local settings helper
	[ "$(sed -n 1p "$STUB_LOG/launcher.args")" = "<--settings>" ]
	settings="$(sed -n 2p "$STUB_LOG/launcher.args")"
	settings="${settings#<}"
	settings="${settings%>}"
	[ "$(printf '%s' "$settings" | jq -r 'keys | join(",")')" = "apiKeyHelper" ]
	helper="$(printf '%s' "$settings" | jq -r .apiKeyHelper)"
	[ "$helper" = "pass show work/$1 | head -1" ]
	: >"$STUB_LOG/pass.args"
	[ "$(PATH="$STUB_BIN:$PATH" STUB_LOG="$STUB_LOG" /bin/sh -c "$helper")" = "sk-fake-$1-SECRET" ]
	[ "$(cat "$STUB_LOG/pass.args")" = "show work/$1" ]
	[ "$(cat "$STUB_LOG/launcher.key")" = "unset" ]
	[ "$(cat "$STUB_LOG/launcher.keyname")" = "$1" ]
}

assert_no_leak() {
	[[ "$output" != *SECRET* ]]
	[[ "$output" == *"after=unset key=unset keyname=unset"* ]]
}

@test "klaude gives the launcher a key helper for the default entry with args intact" {
	run_in_zsh klaude -p 'hello world' '' '*' '$HOME' --model "a b"

	[ "$status" -eq 0 ]
	[ "$(cat "$STUB_LOG/pass.args")" = "show work/ANTHROPIC_SRE_AGENT_KEY" ]
	[ "$(sed -n '3,$p' "$STUB_LOG/launcher.args")" = "$(printf '<%s>\n' -p 'hello world' '' '*' '$HOME' --model 'a b')" ]
	assert_helper_for ANTHROPIC_SRE_AGENT_KEY
	[ ! -e "$STUB_LOG/claude.args" ]
	assert_no_leak
}

@test "klaude -k NAME reads work/NAME and drops -k from the launcher's args" {
	run_in_zsh klaude -k CLAUDE_API_QA_KEY --resume abc

	[ "$status" -eq 0 ]
	[ "$(cat "$STUB_LOG/pass.args")" = "show work/CLAUDE_API_QA_KEY" ]
	[ "$(sed -n '3,$p' "$STUB_LOG/launcher.args")" = "$(printf '<%s>\n' --resume abc)" ]
	assert_helper_for CLAUDE_API_QA_KEY
	[ ! -e "$STUB_LOG/claude.args" ]
	assert_no_leak
}

@test "klaude refuses to start claude when pass has no key" {
	run_in_zsh klaude -k MISSING

	[ "$status" -eq 1 ]
	[ ! -e "$STUB_LOG/launcher.args" ]
	[ ! -e "$STUB_LOG/claude.args" ]
	[[ "$output" == *"klaude: no key in pass work/MISSING"* ]]
}

@test "klaude keeps an ANTHROPIC_API_KEY from the calling shell away from claude" {
	run env ANTHROPIC_API_KEY=sk-inherited-SECRET HOME="$FAKE_HOME" PATH="$STUB_BIN:$PATH" STUB_LOG="$STUB_LOG" \
		zsh -f -c 'source "$1"; klaude' zsh "$ZSH_FILE"

	[ "$status" -eq 0 ]
	[ "$(cat "$STUB_LOG/launcher.key")" = "unset" ]
	[ "$(cat "$STUB_LOG/launcher.keyname")" = "ANTHROPIC_SRE_AGENT_KEY" ]
}

@test "klaude refuses a key name that would break out of the helper command" {
	run_in_zsh klaude -k 'X; touch pwned'

	[ "$status" -eq 1 ]
	[ ! -e "$STUB_LOG/pass.args" ]
	[ ! -e "$STUB_LOG/launcher.args" ]
	[[ "$output" == *"klaude: bad key name"* ]]
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
