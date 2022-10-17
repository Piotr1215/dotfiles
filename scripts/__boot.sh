#!/usr/bin/env bash

# The set -e option instructs bash to immediately exit if any command has a non-zero exit status
# The set -u referencing a previously undefined  variable - with the exceptions of $* and $@ - is an error
# The set -o pipefaile if any command in a pipeline fails, that return code will be used as the return code of the whole pipeline
# https://bit.ly/37nFgin
set -euo pipefail

# Add source and line number wher running in debug mode: bash -xv __boot.sh
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

weekdays=('Monday' 'Tuesday' 'Wednesday' 'Thursday' 'Friday')

current_day=$(date +"%A")

echo "$current_day"

if [[ " ${weekdays[*]} " =~ " $current_day " ]]; then
	fuzzpak slack 2>/dev/null &
	nohup firefox -P "Work" about:profiles >/dev/null 2>&1 &
	alacritty
else
	#Weekend :)
	nohup firefox -P "Home" about:profiles >/dev/null 2>&1 &
	alacritty
fi
