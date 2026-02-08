#!/usr/bin/env bash
set -eo pipefail

# Port of Embed Youtube Link.py - create markdown embed from browser URL
title=$(hyprctl activewindow -j | jq -r '.title')
[[ "$title" != *irefox* && "$title" != *ibreWolf* && "$title" != *hrome* ]] && exit 0

wl-copy ""
wtype -M ctrl -k l -m ctrl
sleep 0.1
wtype -M ctrl -k c -m ctrl
sleep 0.2
url=$(wl-paste 2>/dev/null)
wtype -k Escape

vid=$(echo "$url" | grep -oP '(?:v=|youtu\.be/|shorts/)([^&?\n]+)' | head -1 | sed 's/.*[=/]//')

if [[ -n "$vid" ]]; then
	echo -n "[![Video Thumbnail](https://img.youtube.com/vi/${vid}/0.jpg)](https://www.youtube.com/watch?v=${vid})" | wl-copy
	notify-send "YouTube" "Embed link copied"
else
	echo -n "[${url}](${url})" | wl-copy
	notify-send "YouTube" "Plain link copied"
fi
