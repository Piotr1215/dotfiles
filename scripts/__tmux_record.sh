#!/usr/bin/env bash

recording="$PWD/tmux-$(date +%s).cast"
echo "Recording will start to $recording"
echo "Exit the terminal to stop and save the recording"

asciinema rec "$recording"
