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

	mkdir -p "${HOME}/.cache"

	# Check every 12 hours (nightly builds update frequently)
	if [[ -f "$timestamp_file" ]] && (($(cat "$timestamp_file") > (current_time - 43200))); then
		return 0
	fi

	if ! command -v pipx &>/dev/null; then
		python3 -m pip install --user pipx
		python3 -m pipx ensurepath
	fi

	# Install nightly build (has 403 fixes before stable release)
	pipx install --force yt-dlp --pip-args='--pre' 2>/dev/null || \
		pipx runpip yt-dlp install -U --pre yt-dlp 2>/dev/null

	echo "$current_time" >"$timestamp_file"
}

tracks_file="${HOME}/haruna_playlist.m3u"
if [[ ! -f "$tracks_file" ]]; then
	echo "Error: Track file not found at $tracks_file"
	exit 1
fi

# Parse playlist with awk - output format: "Title | CATEGORY<TAB>URL"
# TAB separates display from URL (URL hidden by fzf delimiter)
track_data=$(awk '
/^# / {
	name = substr($0, 3)
	gsub(/ - YouTube.*/, "", name)
	# Split into category and title
	if (match(name, /^([^:]+): (.+)$/, m)) {
		category = m[1]
		title = m[2]
	} else {
		category = ""
		title = name
	}
}
/^http/ && name {
	if (category) {
		printf "%s | %s\t%s\n", title, category, $0
	} else {
		printf "%s\t%s\n", title, $0
	}
	name = ""
}
' "$tracks_file" | sort)

if [[ -z "$track_data" ]]; then
	echo "Error: No tracks found in the playlist."
	exit 1
fi

# Add line numbers
track_names_with_numbers=$(nl -w2 -n rz -s'. ' <<< "$track_data")

# Main loop for run mode
while true; do
	# In run mode, check for active sessions and add markers
	if [[ "$RUN_MODE" == true ]]; then
		current_display=""
		session_file="/tmp/current_music_session.txt"
		display_file="/tmp/current_music_session_display.txt"

		# Check if session is still running
		if [[ -f "$session_file" ]] && [[ -f "$display_file" ]]; then
			session_name=$(cat "$session_file" 2>/dev/null)
			if tmux has-session -t "$session_name" 2>/dev/null; then
				current_display=$(cat "$display_file" 2>/dev/null)
			fi
		fi

		# Add markers using awk (no subprocess per line)
		marked_tracks=$(echo "$track_names_with_numbers" | awk -v playing="$current_display" '
		{
			# Extract display part: remove "NN. " prefix, then get part before TAB
			line = $0
			sub(/^[0-9]+\. /, "", line)
			split(line, parts, "\t")
			display = parts[1]

			if (playing != "" && display == playing) {
				print "► " $0
			} else {
				print "  " $0
			}
		}')

		# Sort: playing tracks first
		playing=$(echo "$marked_tracks" | grep '^►' || true)
		not_playing=$(echo "$marked_tracks" | grep '^  ' || true)
		[[ -n "$playing" ]] && marked_tracks="$playing"$'\n'"$not_playing" || marked_tracks="$not_playing"

		selected_track_with_number=$(echo "$marked_tracks" | fzf --ansi --reverse --prompt="Select track: " --delimiter=$'\t' --with-nth=1)
	else
		selected_track_with_number=$(echo "$track_names_with_numbers" | fzf --reverse --prompt="Select track: " --delimiter=$'\t' --with-nth=1)
	fi
	
	# Extract line (remove number prefix and marker)
	selected_line=$(echo "$selected_track_with_number" | sed 's/^[►[:space:]]*[0-9]\+\.[[:space:]]*//')

	# Format: "Title | CATEGORY<TAB>URL" - extract both parts
	display_part="${selected_line%%	*}"  # Before TAB
	track_url="${selected_line##*	}"     # After TAB

if [[ -n "$track_url" && "$track_url" == http* ]]; then
	# Extract title for session naming (before the |)
	song_title="${display_part%% |*}"
	song_title="${song_title## }"  # Trim leading space

	# Create session name: lowercase, alphanumeric, max 50 chars
	base_session=$(echo "$song_title" | tr -c '[:alnum:]-' '_' | tr '[:upper:]' '[:lower:]' | cut -c 1-45)
	track_hash=$(echo -n "$display_part" | md5sum | cut -c 1-4)
	tmux_session_name="${base_session}_${track_hash}"

	# Check if THIS exact session already exists (user clicked on playing track to stop it)
	if tmux has-session -t "$tmux_session_name" 2>/dev/null; then
		tmux kill-session -t "$tmux_session_name"
		rm -f "/tmp/current_music_session.txt" "/tmp/current_music_session_display.txt"
		echo "Stopped: $song_title"
	else
		# Kill the previously playing session if it exists
		session_file="/tmp/current_music_session.txt"
		if [[ -f "$session_file" ]]; then
			previous_session=$(cat "$session_file")
			if [[ -n "$previous_session" ]] && tmux has-session -t "$previous_session" 2>/dev/null; then
				tmux kill-session -t "$previous_session" 2>/dev/null || true
			fi
		fi

		# Update yt-dlp in background (ready for next time, doesn't block playback)
		check_and_update_ytdlp &>/dev/null &

		# Create socket directory and path
		socket_dir="${HOME}/.mpv_sockets"
		mkdir -p "$socket_dir"
		socket_path="${socket_dir}/${tmux_session_name}.sock"
		rm -f "$socket_path"

		# Start new tmux session with MPV
		tmux new-session -d -s "$tmux_session_name" \
			mpv --loop-file --no-video --ytdl \
			--ytdl-format="bestaudio/best" \
			--ytdl-raw-options="cookies-from-browser=firefox" \
			--input-ipc-server="$socket_path" \
			"$track_url"

		# Store both session name and display part for fast matching in --run mode
		echo "$tmux_session_name" > "$session_file"
		echo "$display_part" > "${session_file%.txt}_display.txt"
		echo "Playing: $song_title"
	fi

	# Always exit after selection
	break
else
	echo "No track selected. Exiting."
	exit 0
fi

done # End of while loop
