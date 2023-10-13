#!/bin/bash
(
	zenity --info --text="$1" --width=400 &
	pid=$!
	sleep 7
	kill $pid
) &
