#!/usr/bin/env bash

# Launch LibreWolf with YouTube (personal browser)
nohup flatpak run io.gitlab.librewolf-community -P "Home" "https://youtube.com" > /dev/null 2>&1 &
sleep 1
xdotool search --classname librewolf --onlyvisible windowactivate
