#!/usr/bin/env bats

# Drives __tmux_pane_to_session.sh on a private tmux server (its own
# TMUX_TMPDIR) with a stub namer that records its args and stdin and prints
# NAMER_OUT. Never touches the live tmux server.

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	SCRIPT="$REPO_ROOT/scripts/__tmux_pane_to_session.sh"
	export TMUX_TMPDIR="$BATS_TEST_TMPDIR/tmux"
	mkdir -p "$TMUX_TMPDIR"
	unset TMUX TMUX_PANE
	WORK="$BATS_TEST_TMPDIR/proj"
	mkdir -p "$WORK"
	LOG="$BATS_TEST_TMPDIR/namer"
	export TMUX_SESSION_NAMER="$BATS_TEST_TMPDIR/namer.sh"
	cat >"$TMUX_SESSION_NAMER" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >"$LOG.args"
cat >"$LOG.stdin"
[[ -n "\${NAMER_OUT:-}" ]] || exit 1
printf '%s\n' "\$NAMER_OUT"
EOF
	chmod +x "$TMUX_SESSION_NAMER"
	tmux new-session -d -s base -c "$WORK"
	tmux split-window -t base -c "$WORK"
	PANE=$(tmux display-message -p -t base '#{pane_id}')
}

teardown() {
	tmux -S "$TMUX_TMPDIR/tmux-$(id -u)/default" kill-server 2>/dev/null || true
}

# wait_for_session NAME: the background rename lands within a few seconds.
wait_for_session() {
	local i
	for i in $(seq 1 50); do
		tmux has-session -t "=$1" 2>/dev/null && return 0
		sleep 0.1
	done
	return 1
}

sessions() { tmux list-sessions -F '#{session_name}' | sort | tr '\n' ' '; }

@test "a cwd-named session is renamed to the namer's name" {
	NAMER_OUT=tidy-proj-notes run "$SCRIPT" "$PANE"
	[ "$status" -eq 0 ]
	wait_for_session tidy-proj-notes
	[ "$(sessions)" = "base tidy-proj-notes " ]
	grep -qx -- '--where home' "$LOG.args"
	grep -q "(folder $WORK)" "$LOG.stdin"
	grep -q "Last screen lines:" "$LOG.stdin"
}

@test "the move does not wait for the namer" {
	sed -i '2i sleep 3' "$TMUX_SESSION_NAMER"
	local start=$SECONDS
	NAMER_OUT=slow-name run "$SCRIPT" "$PANE"
	[ "$status" -eq 0 ]
	[ $((SECONDS - start)) -lt 2 ]
	tmux has-session -t =proj
}

@test "a failed namer keeps the cwd basename" {
	NAMER_OUT="" run "$SCRIPT" "$PANE"
	[ "$status" -eq 0 ]
	sleep 1
	[ "$(sessions)" = "base proj " ]
}

@test "a name a live session holds is not taken" {
	NAMER_OUT=base run "$SCRIPT" "$PANE"
	sleep 1
	[ "$(sessions)" = "base proj " ]
}

@test "an agent pane keeps its @agent_name and skips the namer" {
	tmux set-option -p -t "$PANE" @agent_name gordon-x
	NAMER_OUT=never-used run "$SCRIPT" "$PANE"
	sleep 1
	[ "$(sessions)" = "base gordon-x " ]
	[ ! -e "$LOG.args" ]
}

@test "a pane under ~/loft is named on the work account" {
	local loft="$BATS_TEST_TMPDIR/home/loft/repo"
	mkdir -p "$loft"
	tmux new-session -d -s other -c "$loft"
	tmux split-window -t other -c "$loft"
	local pane
	pane=$(tmux display-message -p -t other '#{pane_id}')
	HOME="$BATS_TEST_TMPDIR/home" NAMER_OUT=loft-repo-work run "$SCRIPT" "$pane"
	wait_for_session loft-repo-work
	grep -qx -- '--where work' "$LOG.args"
}
