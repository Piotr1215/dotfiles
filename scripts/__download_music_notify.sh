#!/usr/bin/env bash
set -eo pipefail
IFS=$'\n\t'

# Download a YouTube URL as mp3 into ~/music and surface desktop notifications.
#
# Invoked detached from the AutoKey "UrlAndDescription" Playlist action so the
# AutoKey engine is never blocked by the (slow) yt-dlp download + mp3 convert.
# yt-dlp names the file from the video title, so the resulting ~/music/*.mp3
# shows up directly in the Ctrl+U track picker (__play_track.sh).

# AutoKey spawns us with a minimal PATH; pipx/yt-dlp live in ~/.local/bin.
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/go/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

url="$1"
label="${2:-audio}"

download_script="$HOME/dev/dotfiles/scripts/__download_youtube.sh"

notify() { notify-send -i folder-music "Music download" "$1" 2>/dev/null || true; }

if [[ -z "$url" ]]; then
	notify-send -u critical -i dialog-error "Music download" "No URL given" 2>/dev/null || true
	echo "Usage: $(basename "$0") <youtube-url> [label]" >&2
	exit 1
fi

notify "Downloading: $label"

if "$download_script" -mp3 "$url"; then
	notify "Done: $label"
else
	notify-send -u critical -i dialog-error "Music download" "Failed: $label" 2>/dev/null || true
	exit 1
fi
