#!/usr/bin/env bash
set -eo pipefail
IFS=$'\n\t'

check_and_update_ytdlp() {
	local timestamp_file="${HOME}/.cache/ytdlp_last_update"
	local current_time=$(date +%s)

	# Create cache directory if it doesn't exist
	mkdir -p "${HOME}/.cache"

	# Check if timestamp file exists and is less than 24 hours old
	if [[ -f "$timestamp_file" ]] && (($(cat "$timestamp_file") > (current_time - 86400))); then
		return 0
	fi

	if ! command -v pipx &>/dev/null; then
		python3 -m pip install --user pipx
		python3 -m pipx ensurepath
		source ~/.zshrc
	fi
	if ! pipx list | grep -q yt-dlp; then
		pipx install yt-dlp
	else
		pipx upgrade yt-dlp
	fi
	yt-dlp --version

	# Update timestamp
	echo "$current_time" >"$timestamp_file"
}

check_and_update_ytdlp

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

# Find the longest title for proper alignment
max_title_length=0
formatted_track_names=()
track_to_title_map=()
track_to_category_map=()

# First pass - extract titles and categories, find max length
for track in "${track_order[@]}"; do
	# Extract category/type and title parts
	if [[ "$track" =~ ^([^:]+):\ (.+)$ ]]; then
		category="${BASH_REMATCH[1]}"
		title="${BASH_REMATCH[2]}"
		
		# Store title and category separately for length calculation
		track_to_title_map+=("$title")
		track_to_category_map+=("$category")
		
		# Update max title length
		if [[ ${#title} -gt $max_title_length ]]; then
			max_title_length=${#title}
		fi
	else
		# If pattern doesn't match, use as is for title, empty for category
		track_to_title_map+=("$track")
		track_to_category_map+=("")
		
		# Update max title length
		if [[ ${#track} -gt $max_title_length ]]; then
			max_title_length=${#track}
		fi
	fi
done

# Add some padding to max length
max_title_length=$((max_title_length + 2))

# Second pass - create formatted entries with fixed-width alignment
for i in "${!track_to_title_map[@]}"; do
	title="${track_to_title_map[$i]}"
	category="${track_to_category_map[$i]}"
	
	# Create padded title with | separator and category in brackets
	if [[ -n "$category" ]]; then
		# Calculate padding needed
		padding_length=$((max_title_length - ${#title}))
		padding=$(printf '%*s' "$padding_length" '')
		
		# Format with fixed width: "Title     | CATEGORY"
		formatted_track_names+=("$title$padding| $category")
	else
		# If no category, just pad the title
		formatted_track_names+=("$title")
	fi
done

track_names=$(printf "%s\n" "${formatted_track_names[@]}" | sort)
# Add line numbers for easier selection, with consistent alignment
track_names_with_numbers=$(nl -w2 -n rz -s'. ' <<< "$track_names")
selected_track_with_number=$(echo "$track_names_with_numbers" | gum filter --fuzzy)
# Extract just the track name (remove the number prefix)
selected_formatted_track=$(echo "$selected_track_with_number" | sed 's/^[[:space:]]*[0-9]\+\.[[:space:]]*//')

# Map back to the original track name
if [[ "$selected_formatted_track" =~ ^(.+)[[:space:]]*\|[[:space:]]*(.+)$ ]]; then
	title="${BASH_REMATCH[1]}"
	title=$(echo "$title" | sed -e 's/[[:space:]]*$//')  # Trim trailing spaces
	category="${BASH_REMATCH[2]}"
	category=$(echo "$category" | sed -e 's/^[[:space:]]*//')  # Trim leading spaces
	# Try to find the original track name
	for original_track in "${track_order[@]}"; do
		if [[ "$original_track" == "$category: $title" ]]; then
			selected_track="$original_track"
			break
		fi
	done
else
	# If no match, use as is (handle case where there's no category)
	clean_title=$(echo "$selected_formatted_track" | sed -e 's/[[:space:]]*$//')
	selected_track="$clean_title"
fi

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
