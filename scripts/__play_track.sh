#!/usr/bin/env bash
set -eo pipefail
IFS=$'\n\t'

tracks_file="${HOME}/haruna_playlist.m3u"
if [[ ! -f "$tracks_file" ]]; then
	echo "Error: Track file not found at $tracks_file"
	exit 1
fi

declare -A tracks
declare -A display_names
declare -a track_order
current_track_name=""

while IFS= read -r line || [[ -n "$line" ]]; do
	if [[ $line == \#* ]]; then
		current_track_name=${line#\# }
		clean_name="${current_track_name% - YouTube — Mozilla Firefox}"
		display_names["$clean_name"]="$current_track_name"
		track_order+=("$clean_name")
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

track_names=$(printf "%s\n" "${track_order[@]}" | sort)
selected_track=$(echo "$track_names" | gum filter --fuzzy)

if [[ -n $selected_track ]]; then
	# Look up the original name to find the track path
	original_name="${display_names[$selected_track]}"
	track_path="${tracks[$original_name]}"
	# Prepare a valid tmux session name using the clean name
	tmux_session_name=$(echo "$selected_track" | tr -c '[:alnum:]-' '_' | tr '[:upper:]' '[:lower:]' | cut -c 1-25)

	# Create socket directory if it doesn't exist
	socket_dir="${HOME}/.mpv_sockets"
	mkdir -p "$socket_dir"

	# Create unique socket path for this session
	socket_path="${socket_dir}/${tmux_session_name}.sock"

	# Remove existing socket if it exists
	rm -f "$socket_path"

	# Start new tmux session with MPV using the socket
	tmux new-session -d -s "$tmux_session_name" \
		mpv --loop-file --no-video --ytdl \
		--input-ipc-server="$socket_path" \
		"$track_path"

	echo "MPV launched in tmux session: $tmux_session_name"
	echo "Socket created at: $socket_path"
else
	echo "No track selected. Exiting."
	exit 0
fi
