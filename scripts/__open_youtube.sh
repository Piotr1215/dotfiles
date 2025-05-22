#!/usr/bin/env bash

# Launch Firefox with Home profile and YouTube
nohup firefox -P "Home" "https://youtube.com" > /dev/null 2>&1 &
firefox_pid=$!
xdotool search --pid $firefox_pid --onlyvisible --class Firefox windowactivate
