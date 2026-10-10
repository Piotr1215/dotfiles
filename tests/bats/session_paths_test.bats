#!/usr/bin/env bats
#
# Covers __session_paths.sh, the ;;session value-set, without a display or
# live sessions: xdotool, tmux and ps are stubbed, and /proc and the Claude
# homes are fixture trees, so each test builds the process table it judges.

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	SCRIPT="$REPO_ROOT/scripts/__session_paths.sh"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	export PROC_ROOT="$BATS_TEST_TMPDIR/proc"
	CLAUDE_HOME="$BATS_TEST_TMPDIR/claude"
	export CLAUDE_HOMES="$CLAUDE_HOME"
	CODEX_SESSIONS="$BATS_TEST_TMPDIR/codex/sessions/2026/10/10"
	mkdir -p "$STUB_BIN" "$PROC_ROOT" "$CLAUDE_HOME/sessions" "$CODEX_SESSIONS"

	# The focused window's process is $WINDOW_PID.
	cat > "$STUB_BIN/xdotool" <<-'STUB'
		#!/usr/bin/env bash
		case "$1" in getactivewindow) echo 42 ;; getwindowpid) echo "$WINDOW_PID" ;; esac
	STUB
	# tmux clients as "client_pid pane_pid" lines from $BATS_TEST_TMPDIR/clients.
	cat > "$STUB_BIN/tmux" <<-STUB
		#!/usr/bin/env bash
		cat "$BATS_TEST_TMPDIR/clients" 2>/dev/null
	STUB
	# The process table as "pid ppid comm" lines from $BATS_TEST_TMPDIR/ps.
	cat > "$STUB_BIN/ps" <<-STUB
		#!/usr/bin/env bash
		cat "$BATS_TEST_TMPDIR/ps"
	STUB
	chmod +x "$STUB_BIN"/*
	export PATH="$STUB_BIN:$PATH"
	: > "$BATS_TEST_TMPDIR/ps"
}

# proc PID PPID COMM [CWD]: a process in the table, with a working directory.
proc() {
	echo "$1 $2 $3" >> "$BATS_TEST_TMPDIR/ps"
	mkdir -p "$PROC_ROOT/$1/fd"
	[ -z "$4" ] || ln -s "$4" "$PROC_ROOT/$1/cwd"
}

# claude PID SESSION_ID [KIND]: a Claude Code process and its transcript.
claude() {
	echo "{\"pid\":$1,\"sessionId\":\"$2\",\"kind\":\"${3:-interactive}\",\"name\":\"p$1\"}" \
		> "$CLAUDE_HOME/sessions/$1.json"
	mkdir -p "$CLAUDE_HOME/projects/-home-x"
	: > "$CLAUDE_HOME/projects/-home-x/$2.jsonl"
}

# rollout HOLDER_PID NAME CWD: a Codex session file held open by HOLDER_PID.
rollout() {
	echo "{\"type\":\"session_meta\",\"payload\":{\"cwd\":\"$3\"}}" > "$CODEX_SESSIONS/rollout-$2.jsonl"
	ln -s "$CODEX_SESSIONS/rollout-$2.jsonl" "$PROC_ROOT/$1/fd/$RANDOM"
}

@test "a claude in the pane the focused tmux client shows gives its transcript" {
	export WINDOW_PID=10
	proc 10 1 alacritty; proc 11 10 tmux
	proc 20 1 bash; proc 21 20 claude
	echo "11 20" > "$BATS_TEST_TMPDIR/clients"
	claude 21 aaaa
	run "$SCRIPT"
	[ "$status" -eq 0 ]
	[ "$output" = "$CLAUDE_HOME/projects/-home-x/aaaa.jsonl | claude p21" ]
}

@test "a claude in a pane no focused client shows is left out" {
	export WINDOW_PID=10
	proc 10 1 alacritty; proc 11 10 tmux
	proc 20 1 zsh
	proc 30 1 bash; proc 31 30 claude
	printf '11 20\n99 30\n' > "$BATS_TEST_TMPDIR/clients"
	claude 31 bbbb
	run "$SCRIPT"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "a headless claude under the pane's claude is not a session to type" {
	export WINDOW_PID=10
	proc 10 1 alacritty; proc 11 10 tmux
	proc 20 1 bash; proc 21 20 claude; proc 22 21 claude
	echo "11 20" > "$BATS_TEST_TMPDIR/clients"
	claude 21 aaaa; claude 22 cccc print
	run "$SCRIPT"
	[ "$output" = "$CLAUDE_HOME/projects/-home-x/aaaa.jsonl | claude p21" ]
}

@test "a codex pane gives the open rollout started in its directory" {
	export WINDOW_PID=10
	proc 10 1 alacritty; proc 11 10 tmux
	proc 20 1 bash; proc 21 20 node /work/a; proc 22 21 codex /work/a
	proc 50 1 codex /
	echo "11 20" > "$BATS_TEST_TMPDIR/clients"
	rollout 50 mine /work/a
	rollout 50 other /work/b
	run "$SCRIPT"
	[ "$status" -eq 0 ]
	[ "$output" = "$CODEX_SESSIONS/rollout-mine.jsonl | codex /work/a" ]
}

@test "a codex rollout no process holds open is a finished session" {
	export WINDOW_PID=10
	proc 10 1 alacritty; proc 11 10 tmux
	proc 20 1 bash; proc 22 20 codex /work/a
	echo "11 20" > "$BATS_TEST_TMPDIR/clients"
	echo '{"type":"session_meta","payload":{"cwd":"/work/a"}}' > "$CODEX_SESSIONS/rollout-old.jsonl"
	run "$SCRIPT"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "a window running neither claude nor codex prints nothing" {
	export WINDOW_PID=10
	proc 10 1 alacritty; proc 11 10 tmux
	proc 20 1 zsh; proc 21 20 nvim
	echo "11 20" > "$BATS_TEST_TMPDIR/clients"
	run "$SCRIPT"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "a terminal without tmux is searched itself" {
	export WINDOW_PID=10
	proc 10 1 alacritty; proc 12 10 zsh; proc 13 12 claude
	claude 13 dddd
	run "$SCRIPT"
	[ "$output" = "$CLAUDE_HOME/projects/-home-x/dddd.jsonl | claude p13" ]
}

@test "--here finds the claude session this command runs under, not the one on screen" {
	export WINDOW_PID=10 SESSION_FROM_PID=33
	proc 10 1 alacritty; proc 11 10 tmux
	proc 20 1 bash; proc 21 20 claude
	proc 30 1 bash; proc 31 30 claude; proc 32 31 zsh; proc 33 32 bash
	echo "11 20" > "$BATS_TEST_TMPDIR/clients"
	claude 21 aaaa; claude 31 eeee
	run "$SCRIPT" --here
	[ "$status" -eq 0 ]
	[ "$output" = "$CLAUDE_HOME/projects/-home-x/eeee.jsonl | claude p31" ]
}
