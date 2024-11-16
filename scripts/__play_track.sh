#!/usr/bin/env bash

set -eo pipefail
IFS=$'\n\t'

# PROJECT: playlist
tracks_file="${HOME}/haruna_playlist.m3u"
if [[ ! -f "$tracks_file" ]]; then
	echo "Error: Track file not found at $tracks_file"
	exit 1
fi

declare -A tracks
declare -a track_order
current_track_name=""

while IFS= read -r line || [[ -n "$line" ]]; do
	if [[ $line == \#* ]]; then
		current_track_name=${line#\# }
		track_order+=("$current_track_name")
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

# Use track_order array to maintain file order
track_names=$(printf "%s\n" "${track_order[@]}")
selected_track=$(echo "$track_names" | gum filter --fuzzy)

if [[ -n $selected_track ]]; then
	track_path="${tracks[$selected_track]}"
	# Prepare a valid tmux session name: replace spaces, trim to 25 characters max
	tmux_session_name=$(echo "${selected_track// /_}" | cut -c 1-25)

	# Start new tmux session in the background
	tmux new-session -d -s "$tmux_session_name" mpv --loop-file --no-video --ytdl "$track_path"

	echo "MPV launched in tmux session: $tmux_session_name"
	echo "To control MPV, attach to the tmux session using: tmux attach -t $tmux_session_name"
	echo "To stop playback, you can kill the tmux session: tmux kill-session -t $tmux_session_name"
else
	echo "No track selected. Exiting."
	exit 0
fi
