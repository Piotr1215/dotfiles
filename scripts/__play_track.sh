#!/usr/bin/env bash

# Read track names and paths from "${HOME}/haruna_playlist.m3u",
# where comments are track names.
# Select track to play using a fuzzy search interface provided by 'gum'.
# Requires: bash, mpv, gum.

set -eo pipefail

# Set newline and tab as word splitting delimiters
IFS=$'\n\t'

# PROJECT: playlist
tracks_file="${HOME}/haruna_playlist.m3u"

if [[ ! -f "$tracks_file" ]]; then
	echo "Error: Track file not found at $tracks_file"
	exit 1
fi

declare -A tracks
current_track_name=""

while IFS= read -r line || [[ -n "$line" ]]; do
	if [[ $line == \#* ]]; then
		current_track_name=${line#\# }
	elif [[ -n $current_track_name && -n $line ]]; then
		tracks["$current_track_name"]="$line"
	else
		echo "Warning: Malformed line in playlist file. Skipping."
	fi
done <"$tracks_file"

if [ ${#tracks[@]} -eq 0 ]; then
	echo "Error: No tracks found in the playlist."
	exit 1
fi

track_names=$(printf "%s\n" "${!tracks[@]}")

selected_track=$(echo "$track_names" | gum filter --fuzzy)

if [[ -n $selected_track ]]; then
	echo "Playing track: $selected_track"
	nohup mpv --loop-file --no-terminal --no-video "${tracks[$selected_track]}" >/dev/null 2>&1 &
else
	echo "No track selected. Exiting."
	exit 0
fi
