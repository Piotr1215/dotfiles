#!/usr/bin/env bash

# The set -e option instructs bash to immediately exit if any command has a non-zero exit status
# The set -u referencing a previously undefined  variable - with the exceptions of $* and $@ - is an error
# The set -o pipefaile if any command in a pipeline fails, that return code will be used as the return code of the whole pipeline
# https://bit.ly/37nFgin
set -eo pipefail

while true; do
	inotify-hookable \
		--watch-files ~/.config/autokey/data/Scripts/ \
		--on-modify-command "rsync -av --delete --exclude='*.json' ~/.config/autokey/data/Scripts/ ~/dev/dotfiles/.config/autokey/data/Scripts/"
done
