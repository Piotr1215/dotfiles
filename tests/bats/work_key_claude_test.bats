#!/usr/bin/env bats

# Drives klaude, kapi, kcma and kp from .zsh_claude in a bare zsh with stub pass,
# claude, python3 and uv on PATH and a stub claude launcher under the fake HOME.
# run_tty runs the same under a pseudo-terminal (script) for the dim cost lines,
# which print only when stderr is a terminal.
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

	# uv stands in for `uv run --with anthropic python3 <script>`. For __claude_api_run.py it
	# records its args, answers --list-models with one id and writes the models cache, else
	# prints a run record with tokens. For __cma_adhoc.py --list prints the fixture agents,
	# --delete-session prints a deleted record, and a run records its args and stdin, prints
	# the console line, writes PICK-OK to --out and prints an ok record with a cost line that
	# keeps the session under --keep or --session-id.
	cat >"$STUB_LOG/rows.jsonl" <<'EOF'
{"id": "agent_k", "name": "sre-k8s-diagnostician", "model": "claude-opus-5-5", "description": "Reads pods"}
{"id": "agent_p", "name": "claude-adhoc-probe", "model": "claude-haiku-5-5", "description": ""}
EOF
	cat >"$STUB_BIN/uv" <<'EOF'
#!/bin/sh
printf '%s\n' "${ANTHROPIC_API_KEY-unset}" >"$STUB_LOG/uv.key"
case " $* " in
*__claude_api_run.py*)
	printf '<%s>\n' "$@" >"$STUB_LOG/uv.api.args"
	case " $* " in *" --list-models "*)
		mkdir -p "$HOME/.local/state/claude-runs"
		printf 'claude-opus-5-5\tClaude Opus 5.5\tlow,medium,high,xhigh,max\n' >"$HOME/.local/state/claude-runs/models.txt"
		printf 'claude-opus-5-5\n'; exit 0 ;;
	esac
	echo "REPLY-TEXT" >&2
	echo '{"verdict": "ok", "input_tokens": 12, "output_tokens": 3, "cache_read_input_tokens": 0, "cache_creation_input_tokens": 0, "usd_estimate": 0.0004}'
	exit 0 ;;
esac
case " $* " in *" --list "*) printf '<%s>\n' "$@" >"$STUB_LOG/uv.list.args"; cat "$STUB_LOG/rows.jsonl"; exit 0 ;; esac
case " $* " in *" --delete-session "*)
	printf '<%s>\n' "$@" >"$STUB_LOG/uv.delete.args"
	[ -n "$STUB_DELETE_FAIL" ] && { echo '{"deleted": false, "error": "RuntimeError", "status": "error"}'; exit 1; }
	echo '{"deleted": true, "session_id": "sesn_k", "status": "ok"}'; exit 0 ;;
esac
printf '<%s>\n' "$@" >"$STUB_LOG/uv.args"
cat >"$STUB_LOG/uv.stdin"
echo "console: https://console.example/session" >&2
out="" prev="" deleted=true
for a in "$@"; do [ "$prev" = "--out" ] && out="$a"; prev="$a"; done
case " $* " in *" --keep "*|*" --session-id "*) deleted=false ;; esac
[ -n "$out" ] && echo "PICK-OK" >"$out"
echo "{\"status\": \"ok\", \"session_id\": \"sesn_k\", \"deleted\": $deleted, \"cost_line\": \"in 9 out 3 cache read 0 write 0, estimate \$0.0001\"}"
EOF
	chmod +x "$STUB_BIN/uv"
	# fzf picks the row whose second column is $FZF_CHOOSE and records its options.
	cat >"$STUB_BIN/fzf" <<'EOF'
#!/bin/sh
printf '<%s>\n' "$@" >"$STUB_LOG/fzf.args"
awk -F '\t' -v n="$FZF_CHOOSE" '$2 == n'
EOF
	chmod +x "$STUB_BIN/fzf"
	# The headless runner records its args and prompt, then prints what the real one does.
	cat >"$FAKE_HOME/.claude/scripts/__claude_headless_run.sh" <<'EOF'
#!/bin/sh
printf '<%s>\n' "$@" >"$STUB_LOG/headless.args"
while [ $# -gt 0 ]; do
	case "$1" in --prompt-file) pf="$2" ;; --out) out="$2" ;; esac
	shift 2
done
cp "$pf" "$STUB_LOG/headless.prompt"
echo "session 11111111-2222-3333-4444-555555555555"
echo '{"result": "ANSWER-TEXT", "total_cost_usd": 0.0123}' >"$out"
echo '{"subtype":"success","is_error":false,"total_cost_usd":0.0123,"session_id":"s","num_turns":2,"duration_ms":4500}'
EOF
	chmod +x "$FAKE_HOME/.claude/scripts/__claude_headless_run.sh"
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

# Like run_in_zsh under a pseudo-terminal, so [[ -t 2 ]] holds; stdin is /dev/null.
run_tty() {
	local driver="$BATS_TEST_TMPDIR/driver.sh"
	{
		printf 'exec env -u ANTHROPIC_API_KEY HOME=%q PATH=%q STUB_LOG=%q zsh -f -c %q zsh %q' \
			"$FAKE_HOME" "$STUB_BIN:$PATH" "$STUB_LOG" 'source "$1"; shift; "$@"' "$ZSH_FILE"
		printf ' %q' "$@"
		printf ' </dev/null\n'
	} >"$driver"
	run script -qefc "bash $driver" /dev/null
}

DIM=$'\e[2m'
END=$'\e[0m'

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

UV_PY='run --quiet --with anthropic python3'

# Expected uv argv for the API runner: the uv/python prefix, the script, then the given args.
api_argv() {
	printf '<%s>\n' $UV_PY "$FAKE_HOME/.claude/scripts/__claude_api_run.py" "$@"
}

@test "kapi runs the API runner through uv at effort xhigh and prints its record, no cost line off a terminal" {
	run_in_zsh kapi --model claude-opus-5-5 --prompt-file 'my prompt.txt'

	[ "$status" -eq 0 ]
	[ ! -e "$STUB_LOG/pass.args" ]
	[ "$(cat "$STUB_LOG/uv.key")" = "unset" ]
	[ "$(cat "$STUB_LOG/uv.api.args")" = "$(api_argv --pass work/ANTHROPIC_SRE_AGENT_KEY --effort xhigh \
		--model claude-opus-5-5 --prompt-file 'my prompt.txt')" ]
	[[ "$output" == *'"verdict": "ok"'* ]]
	[[ "$output" != *"kapi: in"* ]]
	assert_no_leak
}

@test "kapi keeps an explicit effort and -k entry" {
	run_in_zsh kapi -k CLAUDE_API_QA_KEY -m claude-haiku-5-5 --effort=low

	[ "$status" -eq 0 ]
	[ "$(cat "$STUB_LOG/uv.api.args")" = "$(api_argv --pass work/CLAUDE_API_QA_KEY -m claude-haiku-5-5 --effort=low)" ]
}

@test "kapi at a terminal ends with a dim cost line after the reply" {
	run_tty kapi -m claude-haiku-5-5

	[ "$status" -eq 0 ]
	[[ "$output" == *REPLY-TEXT*"${DIM}kapi: in 12 out 3 cache read 0 write 0, estimate \$0.0004${END}"* ]]
}

@test "kapi --refresh-models lists models through the runner and writes the cache" {
	run_in_zsh kapi --refresh-models

	[ "$status" -eq 0 ]
	[ "$(cat "$STUB_LOG/uv.api.args")" = "$(api_argv --pass work/ANTHROPIC_SRE_AGENT_KEY --list-models)" ]
	[[ "$output" == *claude-opus-5-5* ]]
	[ -s "$FAKE_HOME/.local/state/claude-runs/models.txt" ]
}

models_cache() {
	mkdir -p "$FAKE_HOME/.local/state/claude-runs"
	printf '%s\t%s\t%s\n' claude-opus-5-5 'Claude Opus 5.5' low,medium,high,xhigh,max \
		claude-sonnet-4-6 'Claude Sonnet 4.6' low,medium,high,max claude-haiku-4-5 'Claude Haiku 4.5' - \
		>"$FAKE_HOME/.local/state/claude-runs/models.txt"
}

# Run a completion function with a stub _describe that prints the candidates it gets:
# complete_in_zsh FUNCTION WORD... (the last word is the one being completed).
complete_in_zsh() {
	run env HOME="$FAKE_HOME" PATH="$STUB_BIN:$PATH" STUB_LOG="$STUB_LOG" zsh -f -c '
source "$1"; _describe() { print -rl -- "${(@P)2}"; }
words=("${@:3}"); CURRENT=${#words}; "$2"' zsh "$ZSH_FILE" "$@"
}

@test "kapi -m completes model ids from a fresh cache without calling the API" {
	models_cache
	complete_in_zsh _kapi kapi -m ''

	[ "$status" -eq 0 ]
	[ "$output" = "$(printf '%s\n' 'claude-opus-5-5:Claude Opus 5.5' 'claude-sonnet-4-6:Claude Sonnet 4.6' 'claude-haiku-4-5:Claude Haiku 4.5')" ]
	sleep 0.3
	[ ! -e "$STUB_LOG/uv.api.args" ]
}

@test "kapi --model completion on a day-old cache serves it and refreshes in the background" {
	models_cache
	touch -d '2 days ago' "$FAKE_HOME/.local/state/claude-runs/models.txt"
	complete_in_zsh _kapi kapi --model ''

	[ "$status" -eq 0 ]
	[[ "$output" == "claude-opus-5-5:Claude Opus 5.5"* ]]
	for _ in 1 2 3 4 5 6 7 8 9 10; do [ -e "$STUB_LOG/uv.api.args" ] && break; sleep 0.2; done
	grep -qx -- '<--list-models>' "$STUB_LOG/uv.api.args"
}

@test "a refresh attempt within ten minutes is not repeated" {
	mkdir -p "$FAKE_HOME/.local/state/claude-runs"
	touch "$FAKE_HOME/.local/state/claude-runs/models.txt.try"
	complete_in_zsh _kapi kapi -m ''

	[ -z "$output" ]
	sleep 0.5
	[ ! -e "$STUB_LOG/uv.api.args" ]
}

@test "kp -m completes the Claude Code aliases then the cached ids" {
	models_cache
	complete_in_zsh _kp kp -m ''

	[ "$status" -eq 0 ]
	[ "$(printf '%s\n' "$output" | cut -d: -f1 | tr '\n' ' ')" = "haiku sonnet opus fable claude-opus-5-5 claude-sonnet-4-6 claude-haiku-4-5 " ]
}

@test "kp drops effort to the highest level a cached model takes, with one notice" {
	models_cache
	run_in_zsh kp -m claude-sonnet-4-6 'hi' </dev/null

	[ "$status" -eq 0 ]
	[ "$(sed -n 5,6p "$STUB_LOG/headless.args")" = "$(printf '<%s>\n' --effort high)" ]
	[[ "$output" == *"effort xhigh not accepted by claude-sonnet-4-6; using high"* ]]
}

@test "kp sends no effort to a cached model that takes none, and xhigh to one that takes it" {
	models_cache
	run_in_zsh kp -m claude-haiku-4-5 'hi' </dev/null
	[ "$(sed -n 5,6p "$STUB_LOG/headless.args")" = "$(printf '<%s>\n' --effort '')" ]
	[[ "$output" == *"effort xhigh not accepted by claude-haiku-4-5; sending no effort"* ]]

	run_in_zsh kp -m claude-opus-5-5 'hi' </dev/null
	[ "$(sed -n 5,6p "$STUB_LOG/headless.args")" = "$(printf '<%s>\n' --effort xhigh)" ]
	[[ "$output" != *"not accepted"* ]]
}

# Expected uv argv: the fixed uv/python prefix, the script, then the given args.
uv_argv() {
	printf '<%s>\n' $UV_PY "$FAKE_HOME/.claude/scripts/__cma_adhoc.py" "$@"
}

@test "kcma -k NAME --name passes straight through to the adhoc script" {
	cd "$BATS_TEST_TMPDIR"
	run_in_zsh kcma -k ANTHROPIC_PR_REVIEW_SWARM_KEY --name probe --out 'out file.md' </dev/null

	[ "$status" -eq 0 ]
	[ "$(cat "$STUB_LOG/uv.key")" = "unset" ]
	[ "$(cat "$STUB_LOG/uv.args")" = "$(uv_argv --pass work/ANTHROPIC_PR_REVIEW_SWARM_KEY --name probe --out 'out file.md')" ]
	[ ! -e "$STUB_LOG/uv.list.args" ]
	[[ "$output" == *"console: https://console.example/session"* ]]
	[[ "$output" == *'"status": "ok"'* ]]
	assert_no_leak
}

@test "kcma --name with no --out leaves the default to the script" {
	run_in_zsh kcma --name probe </dev/null

	[ "$status" -eq 0 ]
	[ "$(cat "$STUB_LOG/uv.args")" = "$(uv_argv --pass work/ANTHROPIC_SRE_AGENT_KEY --name probe)" ]
}

@test "kcma with no agent lists agents in fzf and runs the pick with the stdin prompt" {
	printf 'what pods crash?\n' >"$BATS_TEST_TMPDIR/prompt"
	FZF_CHOOSE=sre-k8s-diagnostician run_in_zsh kcma <"$BATS_TEST_TMPDIR/prompt"

	[ "$status" -eq 0 ]
	[ "$(cat "$STUB_LOG/uv.list.args")" = "$(uv_argv --pass work/ANTHROPIC_SRE_AGENT_KEY --list)" ]
	grep -qx -- '<--with-nth=2..>' "$STUB_LOG/fzf.args"
	[ "$(sed -n 1,8p "$STUB_LOG/uv.args")" = "$(uv_argv --pass work/ANTHROPIC_SRE_AGENT_KEY)" ]
	[ "$(sed -n '9,10p' "$STUB_LOG/uv.args")" = "$(printf '<%s>\n' --agent-id agent_k)" ]
	[ "$(sed -n 11p "$STUB_LOG/uv.args")" = "<--out>" ]
	[[ "$(sed -n 12p "$STUB_LOG/uv.args")" == "<$FAKE_HOME/.local/state/claude-runs/kcma-"*".md>" ]]
	[ "$(cat "$STUB_LOG/uv.stdin")" = "what pods crash?" ]
	[[ "$output" == *"console: https://console.example/session"*PICK-OK* ]]
	assert_no_leak
}

@test "kcma AGENT runs that agent without fzf and keeps the rest as the prompt" {
	run_in_zsh kcma --keep claude-adhoc-probe Reply with exactly PICK-OK </dev/null

	[ "$status" -eq 0 ]
	[ ! -e "$STUB_LOG/fzf.args" ]
	[ "$(sed -n '9,11p' "$STUB_LOG/uv.args")" = "$(printf '<%s>\n' --agent-id agent_p --keep)" ]
	[ "$(cat "$STUB_LOG/uv.stdin")" = "Reply with exactly PICK-OK" ]
	[[ "$output" == *PICK-OK* ]]
}

@test "kcma --keep prints the follow-up and delete commands after the answer" {
	run_in_zsh kcma --keep claude-adhoc-probe hi </dev/null

	[ "$status" -eq 0 ]
	[[ "$output" == *PICK-OK*'session sesn_k kept; follow up: kcma --session sesn_k "..."; delete: kcma --delete sesn_k'* ]]
}

@test "kcma without --keep prints no kept-session line" {
	run_in_zsh kcma claude-adhoc-probe hi </dev/null

	[ "$status" -eq 0 ]
	[[ "$output" != *"kept"* ]]
}

@test "kcma --session sends a follow-up turn to that session and keeps it" {
	run_in_zsh kcma --session sesn_k Reply with exactly TURN-2 </dev/null

	[ "$status" -eq 0 ]
	[ ! -e "$STUB_LOG/uv.list.args" ]
	[ "$(sed -n 1,8p "$STUB_LOG/uv.args")" = "$(uv_argv --pass work/ANTHROPIC_SRE_AGENT_KEY)" ]
	[ "$(sed -n 9,11p "$STUB_LOG/uv.args")" = "$(printf '<%s>\n' --session-id sesn_k --out)" ]
	[ "$(cat "$STUB_LOG/uv.stdin")" = "Reply with exactly TURN-2" ]
	[[ "$output" == *PICK-OK*"delete: kcma --delete sesn_k"* ]]
}

@test "kcma --session with no id prints usage and runs nothing" {
	run_in_zsh kcma --session </dev/null

	[ "$status" -eq 1 ]
	[ ! -e "$STUB_LOG/uv.args" ]
	[[ "$output" == *"usage: kcma [-k NAME] --session"* ]]
}

@test "kcma --delete deletes the session through the script" {
	run_in_zsh kcma -k CLAUDE_API_QA_KEY --delete sesn_k

	[ "$status" -eq 0 ]
	[ "$(cat "$STUB_LOG/uv.delete.args")" = "$(uv_argv --pass work/CLAUDE_API_QA_KEY --delete-session sesn_k)" ]
	[[ "$output" == *"deleted sesn_k"* ]]
}

@test "kcma --delete failure prints the record and fails" {
	STUB_DELETE_FAIL=1 run_in_zsh kcma --delete sesn_k

	[ "$status" -eq 1 ]
	[[ "$output" == *'"deleted": false'* ]]
	[[ "$output" != *"deleted sesn_k"* ]]
}

@test "kcma runs end with a dim cost line at a terminal and none off it" {
	run_tty kcma claude-adhoc-probe hi
	[ "$status" -eq 0 ]
	[[ "$output" == *PICK-OK*"${DIM}kcma: in 9 out 3 cache read 0 write 0, estimate \$0.0001${END}"* ]]

	run_tty kcma --session sesn_k hi
	[[ "$output" == *PICK-OK*"kept"*"${DIM}kcma: in 9 out 3"* ]]

	run_tty kcma --name probe
	[[ "$output" == *"${DIM}kcma: in 9 out 3"* ]]

	run_in_zsh kcma claude-adhoc-probe hi </dev/null
	[[ "$output" != *"kcma: in"* ]]
}

@test "kcma KCMA_PICK bypasses fzf and a first word that is no agent stays in the prompt" {
	KCMA_PICK=claude-adhoc-probe run_in_zsh kcma hello there </dev/null

	[ "$status" -eq 0 ]
	[ ! -e "$STUB_LOG/fzf.args" ]
	[ "$(sed -n '9,10p' "$STUB_LOG/uv.args")" = "$(printf '<%s>\n' --agent-id agent_p)" ]
	[ "$(cat "$STUB_LOG/uv.stdin")" = "hello there" ]
}

@test "kcma refuses an unknown KCMA_PICK before starting a session" {
	KCMA_PICK=nope run_in_zsh kcma hi </dev/null

	[ "$status" -eq 1 ]
	[ ! -e "$STUB_LOG/uv.args" ]
	[[ "$output" == *"kcma: no agent named nope"* ]]
}

@test "kcma completion reads agent names from the cache without calling the API" {
	mkdir -p "$FAKE_HOME/.local/state/claude-runs"
	printf '%s\n' 'sre-k8s-diagnostician:claude-opus-5-5, Reads pods' 'claude-adhoc-probe:claude-haiku-5-5' \
		>"$FAKE_HOME/.local/state/claude-runs/cma_agents.txt"
	run_in_zsh _kcma_agent_names

	[ "$status" -eq 0 ]
	[ "$(printf '%s\n' "$output" | sed -n 1,2p)" = "$(printf '%s\n' 'sre-k8s-diagnostician:claude-opus-5-5, Reads pods' 'claude-adhoc-probe:claude-haiku-5-5')" ]
	[ ! -e "$STUB_LOG/uv.key" ]
}

@test "kp runs the headless runner with read-only defaults in the current dir" {
	cd "$BATS_TEST_TMPDIR"
	run_in_zsh kp 'what does this repo do?' </dev/null

	[ "$status" -eq 0 ]
	local args
	args="$(cat "$STUB_LOG/headless.args")"
	[ "$(printf '%s\n' "$args" | sed -n 1,10p)" = "$(printf '<%s>\n' --key ANTHROPIC_SRE_AGENT_KEY --model sonnet --effort xhigh \
		--allowed-tools 'Read,Grep,Glob,Bash(rg:*),Bash(fd:*),Bash(ls:*),Bash(sed:*)' --cwd "$BATS_TEST_TMPDIR")" ]
	[[ "$args" == *"<$FAKE_HOME/.local/state/claude-runs/kp-"*".prompt>"* ]]
	[ "$(cat "$STUB_LOG/headless.prompt")" = "what does this repo do?" ]
	[ "$(printf '%s\n' "$output" | sed -n 1,3p)" = "$(printf '%s\n' 'session 11111111-2222-3333-4444-555555555555' \
		ANSWER-TEXT 'after=unset key=unset keyname=unset')" ]
	assert_no_leak
}

@test "kp at a terminal ends with a dim cost line" {
	cd "$BATS_TEST_TMPDIR"
	run_tty kp 'what does this repo do?'

	[ "$status" -eq 0 ]
	[[ "$output" == *ANSWER-TEXT*"${DIM}kp: cost \$0.0123 turns 2 4s success${END}"* ]]
}

@test "kp takes -k -m -e -t and a prompt on stdin" {
	printf 'from stdin\n' >"$BATS_TEST_TMPDIR/prompt"
	run_in_zsh kp -k CLAUDE_API_QA_KEY -m opus -e high -t 'Read' <"$BATS_TEST_TMPDIR/prompt"

	[ "$status" -eq 0 ]
	[ "$(sed -n 1,8p "$STUB_LOG/headless.args")" = "$(printf '<%s>\n' --key CLAUDE_API_QA_KEY --model opus --effort high --allowed-tools Read)" ]
	[ "$(cat "$STUB_LOG/headless.prompt")" = "from stdin" ]
}

@test "kp with no prompt prints usage and runs nothing" {
	run_in_zsh kp -m opus </dev/null

	[ "$status" -eq 1 ]
	[ ! -e "$STUB_LOG/headless.args" ]
	[[ "$output" == *"usage: kp"* ]]
}
