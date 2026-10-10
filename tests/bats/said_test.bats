#!/usr/bin/env bats
#
# Covers __said.sh: what the user typed in a Claude Code or Codex session,
# without the harness text around it. Session files are fixtures; finding the
# session from the calling process is __session_paths.sh --here's job and is
# covered in session_paths_test.bats.

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	SAID="$REPO_ROOT/scripts/__said.sh"
}

@test "a claude transcript gives the typed messages and ! commands, nothing the harness wrote" {
	f="$BATS_TEST_TMPDIR/claude.jsonl"
	cat > "$f" <<-'JSONL'
		{"type":"user","message":{"role":"user","content":"is this any good?"}}
		{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"It is."}]}}
		{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}
		{"type":"user","message":{"role":"user","content":"<system-reminder>be brief</system-reminder>"}}
		{"type":"user","isMeta":true,"message":{"role":"user","content":"Base directory for this skill: /x"}}
		{"type":"user","message":{"role":"user","content":"<bash-input>classif \"q\" -s</bash-input>"}}
		{"type":"user","message":{"role":"user","content":"<bash-stdout>yes 0.9</bash-stdout><bash-stderr></bash-stderr>"}}
		{"type":"user","message":{"role":"user","content":[{"type":"text","text":"two\nlines"},{"type":"text","text":"<system-reminder>x</system-reminder>"}]}}
		{"type":"user","message":{"role":"user","content":"This session is being continued from a previous conversation that ran out of context."}}
	JSONL
	run "$SAID" "$f"
	[ "$status" -eq 0 ]
	[ "$output" = "$(printf 'is this any good?\n\n! classif "q" -s\n\ntwo\nlines\n')" ]
}

@test "a codex rollout gives the typed messages, not its instructions or environment" {
	f="$BATS_TEST_TMPDIR/rollout-x.jsonl"
	cat > "$f" <<-'JSONL'
		{"type":"session_meta","payload":{"cwd":"/w"}}
		{"type":"response_item","payload":{"type":"message","role":"developer","content":[{"type":"input_text","text":"rules"}]}}
		{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"# AGENTS.md instructions\n\nbe good"}]}}
		{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>cwd</environment_context>"}]}}
		{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"reply ok"}]}}
		{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"ok"}]}}
	JSONL
	run "$SAID" "$f"
	[ "$status" -eq 0 ]
	[ "$output" = "reply ok" ]
}

@test "outside a session and with no file it says what to pass" {
	run env SESSION_FROM_PID=1 "$SAID"
	[ "$status" -eq 1 ]
	[[ "$output" == *"pass a session file"* ]]
}

@test "run through a symlink on PATH it still finds its helper" {
	ln -s "$SAID" "$BATS_TEST_TMPDIR/said"
	run env SESSION_FROM_PID=1 "$BATS_TEST_TMPDIR/said"
	[ "$status" -eq 1 ]
	[[ "$output" == *"pass a session file"* ]]
}
