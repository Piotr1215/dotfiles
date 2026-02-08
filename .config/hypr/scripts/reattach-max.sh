#!/usr/bin/env bash
set -eo pipefail

# Port of ReattachAndMax.py - reattach browser tab, maximize
title=$(hyprctl activewindow -j | jq -r '.title')
[[ "$title" != *irefox* && "$title" != *ibreWolf* ]] && exit 0

wtype -M shift -M alt -k a -m alt -m shift
sleep 0.3
~/.config/hypr/scripts/layouts.sh 5
