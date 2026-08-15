#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	TMUX_SOCKET_DIR=$(mktemp -d /tmp/tmux-pane-menu-bats-XXXXXX)
	SOCKET_NAME="pane-menu-${BATS_TEST_NUMBER}-$$"
}

private_tmux() {
	env -u TMUX TMUX_TMPDIR="$TMUX_SOCKET_DIR" \
		tmux -L "$SOCKET_NAME" -f /dev/null "$@"
}

teardown() {
	private_tmux kill-server 2>/dev/null || true
	rm -rf "$TMUX_SOCKET_DIR"
}

@test "right-click pane menu types the clicked line without submitting it" {
	private_tmux new-session -d -s pane-menu
	[ "$(private_tmux list-sessions -F '#S')" = "pane-menu" ]
	[[ "$(private_tmux display-message -p '#{socket_path}')" == "$TMUX_SOCKET_DIR"/* ]]

	private_tmux source-file "$REPO_ROOT/.tmux.conf"
	binding=$(private_tmux list-keys -T root | awk '$4 == "MouseDown3Pane"')
	[[ "$binding" == *'"#{?mouse_line,Type Line,}" C-l { copy-mode -q ; send-keys -l "#{q:mouse_line}" }'* ]]
	[[ "$binding" != *'send-keys Enter'* ]]

	private_tmux kill-server
	run private_tmux has-session -t pane-menu
	[ "$status" -ne 0 ]
}
