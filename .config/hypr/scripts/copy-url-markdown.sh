#!/usr/bin/env bash
set -eo pipefail

# Port of autokey "Copy URL in markdown1.py" for Wayland
# Gets selected text + browser URL, formats as [text](url)

title=$(hyprctl activewindow -j | jq -r '.title')
[[ "$title" != *irefox* && "$title" != *ibreWolf* && "$title" != *hrome* ]] && exit 0

description=$(wl-paste -p 2>/dev/null || true)
wl-copy ""
wtype -M ctrl -k l -m ctrl
sleep 0.1
wtype -M ctrl -k c -m ctrl
sleep 0.2
url=$(wl-paste 2>/dev/null || true)
wtype -k Escape

[[ -z "$url" ]] && exit 0
combined="[${description:-$title}](${url})"
echo -n "$combined" | wl-copy
notify-send "Markdown" "$combined"
