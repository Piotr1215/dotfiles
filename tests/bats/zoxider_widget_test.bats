#!/usr/bin/env bats

# Drives the Alt-j zoxider widget from .zshrc in a private tmux server, with
# real zoxide and fzf, a scratch zoxide database, and a stubbed xsel.

setup() {
	command -v tmux >/dev/null && command -v zoxide >/dev/null && command -v fzf >/dev/null ||
		skip "needs tmux, zoxide and fzf"

	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	TMUX_SOCKET_DIR=$(mktemp -d /tmp/tmux-zoxider-bats-XXXXXX)
	SOCKET_NAME="zoxider-${BATS_TEST_NUMBER}-$$"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	ZO_DIR="$BATS_TEST_TMPDIR/zoxide"
	CLIP="$BATS_TEST_TMPDIR/clipboard"
	mkdir -p "$STUB_BIN" "$ZO_DIR"

	printf '#!/bin/sh\ncat > "%s"\n' "$CLIP" >"$STUB_BIN/xsel"
	chmod +x "$STUB_BIN/xsel"

	# The widget as .zshrc defines it, not a copy of it.
	WIDGET="$BATS_TEST_TMPDIR/zoxider.zsh"
	sed -n '/^function zoxider()/,/^bindkey .\^\[j. zoxider/p' "$REPO_ROOT/.zshrc" >"$WIDGET"
	grep -q "zle -N zoxider" "$WIDGET"
}

teardown() {
	private_tmux kill-server 2>/dev/null || true
	rm -rf "$TMUX_SOCKET_DIR"
}

private_tmux() {
	env -u TMUX TMUX_TMPDIR="$TMUX_SOCKET_DIR" \
		tmux -L "$SOCKET_NAME" -f /dev/null "$@"
}

# Wait up to 5s for the pane to show (or, with !, stop showing) a fixed string.
wait_for_pane() {
	local negate=0
	[[ $1 == "!" ]] && { negate=1; shift; }
	local i
	for i in $(seq 50); do
		if private_tmux capture-pane -p | grep -qF -- "$1"; then
			((negate)) || return 0
		else
			((negate)) && return 0
		fi
		sleep 0.1
	done
	echo "pane never settled on: $( ((negate)) && echo "not ")$1" >&2
	private_tmux capture-pane -p >&2
	return 1
}

# Start zsh with only the widget loaded, type a partial command, open Alt-j.
open_picker_over() {
	local target=$1
	_ZO_DATA_DIR="$ZO_DIR" zoxide add "$target"
	private_tmux new-session -d -x 200 -y 30 \
		"env PATH='$STUB_BIN:$PATH' _ZO_DATA_DIR='$ZO_DIR' zsh -f"
	private_tmux send-keys "source '$WIDGET'; setopt autocd; PS1='P> '; clear" C-m
	wait_for_pane "P>"
	private_tmux send-keys "echo typed"
	private_tmux send-keys M-j
	wait_for_pane "1/1"
}

@test "ctrl-y copies the highlighted path and keeps the command line" {
	mkdir -p "$BATS_TEST_TMPDIR/dir with space"
	target=$(realpath "$BATS_TEST_TMPDIR/dir with space")
	open_picker_over "$target"

	private_tmux send-keys C-y
	wait_for_pane ! "1/1"

	[ "$(cat "$CLIP")" = "$target" ]
	private_tmux capture-pane -p | grep -qx "P> echo typed"
}

@test "esc copies nothing and keeps the command line" {
	mkdir -p "$BATS_TEST_TMPDIR/somewhere"
	open_picker_over "$(realpath "$BATS_TEST_TMPDIR/somewhere")"

	private_tmux send-keys Escape
	wait_for_pane ! "1/1"

	[ ! -e "$CLIP" ]
	private_tmux capture-pane -p | grep -qx "P> echo typed"
}

@test "enter still jumps to the picked directory" {
	mkdir -p "$BATS_TEST_TMPDIR/jumphere"
	target=$(realpath "$BATS_TEST_TMPDIR/jumphere")
	open_picker_over "$target"

	private_tmux send-keys Enter
	wait_for_pane ! "1/1"
	private_tmux send-keys 'print -r -- "PWD=$PWD"' C-m

	wait_for_pane "PWD=$target"
	[ ! -e "$CLIP" ]
}
