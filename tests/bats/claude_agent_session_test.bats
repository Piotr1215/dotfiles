#!/usr/bin/env bats

# Drives ca from .zsh_claude in a bare zsh with a fake HOME: a fixture agents
# folder, a stub __claude_with_monitor.sh that records its args, and a stub fzf
# that records its input and answers with the row named in FZF_ANSWER.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	ZSH_FILE="$REPO_ROOT/.zsh_claude"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	STUB_LOG="$BATS_TEST_TMPDIR/log"
	FAKE_HOME="$BATS_TEST_TMPDIR/home"
	AGENTS="$FAKE_HOME/.claude/agents"
	mkdir -p "$STUB_BIN" "$STUB_LOG" "$AGENTS" "$FAKE_HOME/.claude/scripts"

	cat >"$AGENTS/history-finder.md" <<'EOF'
---
name: history-finder
description: >-
  Read-only history finder. Finds when and why
  something happened.
tools: All tools
model: haiku
effort: low
omitClaudeMd: true
---

Body text with name: not-a-field
EOF
	cat >"$AGENTS/researcher.md" <<'EOF'
---
name: researcher
description: "Web research specialist with sources."
---
Body.
EOF
	printf 'no frontmatter here\n' >"$AGENTS/notes.md"

	cat >"$FAKE_HOME/.claude/scripts/__claude_with_monitor.sh" <<'EOF'
#!/bin/sh
printf '<%s>\n' "$@" >"$STUB_LOG/launcher.args"
EOF
	cat >"$STUB_BIN/fzf" <<'EOF'
#!/bin/sh
cat >"$STUB_LOG/fzf.input"
[ -n "$FZF_ANSWER" ] || exit 130
grep "^$FZF_ANSWER	" "$STUB_LOG/fzf.input"
EOF
	chmod +x "$FAKE_HOME/.claude/scripts/__claude_with_monitor.sh" "$STUB_BIN/fzf"
}

run_ca() {
	run env HOME="$FAKE_HOME" PATH="$STUB_BIN:$PATH" STUB_LOG="$STUB_LOG" \
		zsh -f -c 'source "$1"; shift; "$@"' zsh "$ZSH_FILE" "$@"
}

@test "rows read name, model, effort and a folded description from frontmatter" {
	run_ca _ca_rows
	[ "$status" -eq 0 ]
	[[ "$output" == *$'history-finder\thaiku\tlow\tRead-only history finder. Finds when and why something happened.'* ]]
	[[ "$output" == *$'researcher\tinherit\t-\tWeb research specialist with sources.'* ]]
	[[ "$output" != *not-a-field* ]]
}

@test "a file without frontmatter is listed by its file name" {
	run_ca _ca_rows
	[[ "$output" == *$'notes\tinherit\t-\t'* ]]
}

@test "ca AGENT runs the session as that agent and passes the rest through" {
	run_ca ca history-finder "why did this change" --model sonnet
	[ "$status" -eq 0 ]
	[ ! -e "$STUB_LOG/fzf.input" ]
	[ "$(cat "$STUB_LOG/launcher.args")" = "$(printf '<%s>\n' --agent history-finder 'why did this change' --model sonnet)" ]
}

@test "ca without an agent picks one in fzf and keeps the words as the prompt" {
	FZF_ANSWER=researcher run_ca ca find the release notes
	[ "$status" -eq 0 ]
	[[ "$(cat "$STUB_LOG/fzf.input")" == *history-finder* ]]
	[ "$(cat "$STUB_LOG/launcher.args")" = "$(printf '<%s>\n' --agent researcher find the release notes)" ]
}

@test "a cancelled pick starts nothing" {
	run_ca ca
	[ "$status" -ne 0 ]
	[ ! -e "$STUB_LOG/launcher.args" ]
}

@test "CA_PICK skips fzf and refuses an unknown agent before launch" {
	CA_PICK=researcher run_ca ca hello
	[ "$status" -eq 0 ]
	[ ! -e "$STUB_LOG/fzf.input" ]
	[ "$(cat "$STUB_LOG/launcher.args")" = "$(printf '<%s>\n' --agent researcher hello)" ]
	rm -f "$STUB_LOG/launcher.args"
	CA_PICK=nope run_ca ca hello
	[ "$status" -eq 1 ]
	[[ "$output" == *"ca: no agent named nope"* ]]
	[ ! -e "$STUB_LOG/launcher.args" ]
}

@test "completion entries carry model and effort before the description" {
	run_ca _ca_completions
	[ "$status" -eq 0 ]
	[[ "$output" == *"history-finder:haiku/low  Read-only history finder."* ]]
	[[ "$output" == *"researcher:inherit/-  Web research specialist with sources."* ]]
}
