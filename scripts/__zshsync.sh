#!/bin/bash

cd /home/decoder/dev/dotfiles || exit
while true; do
	inotify-hookable \
		--watch-files ./ \
		--on-modify-command "git add . && git commit -m 'auto commit' && git push origin master"
done
