#!/usr/bin/env bash

# The set -e option instructs bash to immediately exit if any command has a non-zero exit status
# The set -u referencing a previously undefined  variable - with the exceptions of $* and $@ - is an error
# The set -o pipefaile if any command in a pipeline fails, that return code will be used as the return code of the whole pipeline
# https://bit.ly/37nFgin
set -euo pipefail
# Set new line and tab for word splitting
IFS=$'\n\t'

session=$(tmux display-message -p '#S')
tmux detach -s "$session"
asciinema rec --command "tmux attach -t $session" "$PWD"/tmux-$(date +%F--%H%M).cast