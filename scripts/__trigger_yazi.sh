#!/usr/bin/env bash

y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	EDITOR=nvim yazi "$@" --cwd-file="$tmp"
	if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
		tmux send-keys "cd $cwd" C-m
	fi
	rm -f -- "$tmp"
}

current_command=$(tmux display-message -p '#{pane_current_command}')

if [[ "$current_command" == "nvim" ]]; then
	tmux send-keys 'Space' '-'
else
	tmux popup -d '#{pane_current_path}' -E -h 95% -w 95% -x 100% "bash -c 'source $0; y'"
fi
