#!/usr/bin/env bash
set -euo pipefail
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

if [ -z ${2+x} ]; then
	echo "Second argument is unset" >>/tmp/taskopen_debug.log
else
	echo "Second argument is set to '$2'" >>/tmp/taskopen_debug.log
fi

taskopen "$1"
