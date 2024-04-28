#!/usr/bin/env bash

set -eo pipefail

# Add source and line number wher running in debug mode: __run_with_xtrace.sh __restart_nvim.sh
# Set new line and tab for word splitting
IFS=$'\n\t'

if [ -z "$TMUX" ]; then
	echo "This script must be run from inside a tmux session."
	exit 1
fi

TMUX_PANE=$(tmux display-message -p '#D')

tmux send-keys -t "$TMUX_PANE" 'Escape' C-m ':wq' C-m

sleep 0.5

# Detach the script from Neovim and wait a bit to ensure Neovim exits
# PROJECT: nvim-restart
(nohup bash -c " sleep 0.5; tmux send-keys -t \"$TMUX_PANE\" 'lvim' C-m " &>/dev/null &)
