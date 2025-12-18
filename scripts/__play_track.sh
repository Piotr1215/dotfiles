#!/usr/bin/env bash
set -eo pipefail
IFS=$'\n\t'

# Check for --help flag
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
	cat <<-EOF
	Usage: $(basename "$0") [OPTIONS]
	
	Play audio tracks from playlist using mpv in tmux sessions.
	
	OPTIONS:
	  --run     Run in continuous mode (stay open after selection)
	  --help    Show this help message
	
	BEHAVIOR:
	  - Displays tracks from a playlist
	  - Plays selected track in a tmux session using mpv
	  - Only one track plays at a time (stops others automatically)
	  - In --run mode: shows playing tracks with ► marker
	  - Click playing track again to stop it
	
	REQUIREMENTS:
	  - tmux, mpv, fzf, yt-dlp (auto-installed via pipx)
	  - Playlist file at ~/haruna_playlist.m3u
	EOF
	exit 0
fi

# Check for --run flag
RUN_MODE=false
if [[ "$1" == "--run" ]]; then
	RUN_MODE=true
fi

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

# First pass - extract titles and categories, find max display width
for track in "${track_order[@]}"; do
	# Extract category/type and title parts
	if [[ "$track" =~ ^([^:]+):\ (.+)$ ]]; then
		category="${BASH_REMATCH[1]}"
		title="${BASH_REMATCH[2]}"
		
		# Store title and category separately for length calculation
		track_to_title_map+=("$title")
		track_to_category_map+=("$category")
		
		# Calculate display width (handles emojis and unicode properly)
		title_width=$(echo -n "$title" | wc -L)
		if [[ $title_width -gt $max_title_length ]]; then
			max_title_length=$title_width
		fi
	else
		# If pattern doesn't match, use as is for title, empty for category
		track_to_title_map+=("$track")
		track_to_category_map+=("")
		
		# Calculate display width
		track_width=$(echo -n "$track" | wc -L)
		if [[ $track_width -gt $max_title_length ]]; then
			max_title_length=$track_width
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
		# Calculate padding needed based on display width
		title_width=$(echo -n "$title" | wc -L)
		padding_length=$((max_title_length - title_width))
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

# Main loop for run mode
while true; do
	# In run mode, check for active sessions and add markers
	if [[ "$RUN_MODE" == true ]]; then
		# Read the currently playing session from file
		current_playing_session=""
		if [[ -f "/tmp/current_music_session.txt" ]]; then
			current_playing_session=$(cat "/tmp/current_music_session.txt" 2>/dev/null || true)
		fi
		
		# Add markers to active tracks
		marked_tracks=""
		while IFS= read -r line; do
			track_only=$(echo "$line" | sed 's/^[[:space:]]*[0-9]\+\.[[:space:]]*//')
			
			# Reconstruct the full track name from the formatted display
			if [[ "$track_only" =~ ^(.+)[[:space:]]*\|[[:space:]]*(.+)$ ]]; then
				title="${BASH_REMATCH[1]}"
				title=$(echo "$title" | sed -e 's/[[:space:]]*$//')  # Trim trailing spaces
				category="${BASH_REMATCH[2]}"
				category=$(echo "$category" | sed -e 's/^[[:space:]]*//')  # Trim leading spaces
				full_track="$category: $title"
			else
				full_track="$track_only"
			fi
			
			# Create potential session name from full track (same logic as when creating session)
			# Extract just the title part for session naming
			if [[ "$full_track" =~ ^[^:]+:\ (.+)$ ]]; then
				song_title="${BASH_REMATCH[1]}"
			else
				song_title="$full_track"
			fi
			
			# Create session name with hash suffix for uniqueness
			base_session=$(echo "$song_title" | tr -c '[:alnum:]-' '_' | tr '[:upper:]' '[:lower:]' | cut -c 1-45)
			track_hash=$(echo -n "$full_track" | md5sum | cut -c 1-4)
			potential_session="${base_session}_${track_hash}"
			
			# Check if this is the currently playing session
			is_playing=false
			if [[ "$potential_session" == "$current_playing_session" ]]; then
				# Also verify the session actually exists
				if tmux has-session -t "$potential_session" 2>/dev/null; then
					is_playing=true
				fi
			fi
			
			if $is_playing; then
				marked_tracks+="► $line"$'\n'
			else
				marked_tracks+="  $line"$'\n'
			fi
		done <<< "$track_names_with_numbers"
		
		# Sort marked tracks so playing tracks (with ►) appear first
		playing_tracks=$(echo -n "$marked_tracks" | grep '^►' || true)
		not_playing_tracks=$(echo -n "$marked_tracks" | grep '^  ' || true)
		
		if [[ -n "$playing_tracks" && -n "$not_playing_tracks" ]]; then
			marked_tracks="$playing_tracks"$'\n'"$not_playing_tracks"
		elif [[ -n "$playing_tracks" ]]; then
			marked_tracks="$playing_tracks"
		else
			marked_tracks="$not_playing_tracks"
		fi
		
		selected_track_with_number=$(echo "$marked_tracks" | fzf --ansi --reverse --prompt="Select track: ")
	else
		selected_track_with_number=$(echo "$track_names_with_numbers" | fzf --reverse --prompt="Select track: ")
	fi
	
	# Extract just the track name (remove the number prefix and marker if present)
	selected_formatted_track=$(echo "$selected_track_with_number" | sed 's/^[►[:space:]]*[0-9]\+\.[[:space:]]*//')

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
	# Generate unique session name from the song title (not category)
	# Extract just the title part for session naming
	if [[ "$selected_track" =~ ^[^:]+:\ (.+)$ ]]; then
		song_title="${BASH_REMATCH[1]}"
	else
		song_title="$selected_track"
	fi
	
	# Create session name: lowercase, alphanumeric, max 50 chars
	# Use more characters and add a hash suffix for uniqueness
	base_session=$(echo "$song_title" | tr -c '[:alnum:]-' '_' | tr '[:upper:]' '[:lower:]' | cut -c 1-45)
	# Add a short hash of the full track name for uniqueness
	track_hash=$(echo -n "$selected_track" | md5sum | cut -c 1-4)
	tmux_session_name="${base_session}_${track_hash}"

	# Check if THIS exact session already exists (user clicked on playing track to stop it)
	if tmux has-session -t "$tmux_session_name" 2>/dev/null; then
		# Kill existing session
		tmux kill-session -t "$tmux_session_name"
		# Remove the session file since nothing is playing now
		rm -f "/tmp/current_music_session.txt"
		echo "Stopped: $selected_track"
	else
		# Kill the previously playing session if it exists
		session_file="/tmp/current_music_session.txt"
		if [[ -f "$session_file" ]]; then
			previous_session=$(cat "$session_file")
			if [[ -n "$previous_session" ]] && tmux has-session -t "$previous_session" 2>/dev/null; then
				tmux kill-session -t "$previous_session" 2>/dev/null || true
				echo "Stopped previous: $previous_session"
			fi
		fi
		
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
			--ytdl-format="bestaudio/best" \
			--input-ipc-server="$socket_path" \
			"$track_path"

		# Store the session name for future reference
		echo "$tmux_session_name" > "$session_file"
		
		echo "Playing: $selected_track"
	fi
	
	# If not in run mode, exit after single operation
	if [[ "$RUN_MODE" != true ]]; then
		break
	fi
else
	echo "No track selected. Exiting."
	exit 0
fi

done # End of while loop
