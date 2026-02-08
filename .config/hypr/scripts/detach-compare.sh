#!/usr/bin/env bash
set -eo pipefail

# Port of DetachAndCompare.py - detach browser tab, side-by-side
title=$(hyprctl activewindow -j | jq -r '.title')
[[ "$title" != *irefox* && "$title" != *ibreWolf* ]] && exit 0

wtype -M shift -M alt -k d -m alt -m shift
sleep 0.3
~/.config/hypr/scripts/layouts.sh 3
