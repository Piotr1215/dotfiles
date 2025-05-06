#!/usr/bin/env bash
set -eo pipefail
IFS=$'\n\t'

socket_dir="${HOME}/.mpv_sockets"
tracks_file="${HOME}/haruna_playlist.m3u"

[[ ! -f "$tracks_file" ]] && { echo "Error: Track file not found"; exit 1; }

# Parse the playlist
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
    fi
done <"$tracks_file"

[[ ${#tracks[@]} -eq 0 ]] && { echo "Error: No tracks found"; exit 1; }

# Find current track
current_index=-1
music_sessions=()
shopt -s nullglob
for sock in "${socket_dir}"/*.sock; do
    [[ -S "$sock" ]] || continue
    session_name=$(basename "$sock" .sock)
    tmux has-session -t "$session_name" 2>/dev/null || continue
    music_sessions+=("$session_name")
done

if [[ ${#music_sessions[@]} -gt 0 ]]; then
    current_session="${music_sessions[0]}"
    for i in "${!track_order[@]}"; do
        track="${track_order[$i]}"
        # Extract song name from "CATEGORY: SONG"
        if [[ "$track" =~ ^([^:]+):\ (.+)$ ]]; then
            song_name="${BASH_REMATCH[2]}"
        else
            song_name="$track"
        fi
        
        tmux_name=$(echo "$song_name" | tr -c '[:alnum:]-' '_' | tr '[:upper:]' '[:lower:]' | cut -c 1-25)
        [[ "$current_session" == "$tmux_name" ]] || continue
        
        current_index=$i
        tmux kill-session -t "$current_session" 2>/dev/null
        break
    done
fi

# Select next track (or first if none playing)
if [[ $current_index -ge 0 ]]; then
    next_index=$(( (current_index + 1) % ${#track_order[@]} ))
else
    next_index=0
fi

next_track="${track_order[$next_index]}"
original_name="${display_names[$next_track]}"
track_path="${tracks[$original_name]}"

# Extract song name for session naming
if [[ "$next_track" =~ ^([^:]+):\ (.+)$ ]]; then
    song_title="${BASH_REMATCH[2]}"
else
    song_title="$next_track"
fi
tmux_session_name=$(echo "$song_title" | tr -c '[:alnum:]-' '_' | tr '[:upper:]' '[:lower:]' | cut -c 1-25)

# Start new tmux session with MPV
mkdir -p "$socket_dir"
socket_path="${socket_dir}/${tmux_session_name}.sock"
rm -f "$socket_path"

tmux new-session -d -s "$tmux_session_name" \
    mpv --loop-file --no-video --ytdl \
    --input-ipc-server="$socket_path" \
    "$track_path"

echo "Playing: $next_track"