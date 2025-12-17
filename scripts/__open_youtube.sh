#!/usr/bin/env bash

# Launch LibreWolf with Home profile and YouTube
nohup firefox -P "Home" "https://youtube.com" > /dev/null 2>&1 &
sleep 1
xdotool search --classname Navigator --onlyvisible windowactivate
