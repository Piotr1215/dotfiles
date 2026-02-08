#!/usr/bin/env bash
set -eo pipefail

# Port of DownloadMusic.py - download YouTube as MP3
music_dir="$HOME/music"
url=$(wl-paste 2>/dev/null)

[[ -z "$url" || "$url" != *youtu* ]] && { notify-send "Music" "No YouTube URL in clipboard"; exit 0; }

title=$(yt-dlp --get-filename -o '%(title)s' --restrict-filenames --no-playlist "$url" 2>/dev/null)
expected="$music_dir/${title}.mp3"

if [[ -f "$expected" ]]; then
	notify-send "Music" "Already exists: $title"
	exit 0
fi

~/dev/dotfiles/scripts/__download_youtube.sh -mp3 "$url" &
notify-send "Music" "Downloading: $title"
wl-copy ""
