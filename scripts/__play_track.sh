#!/usr/bin/env bash
set -eo pipefail
IFS=$'\n\t'

# Check for --help flag
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
	cat <<-EOF
	Usage: $(basename "$0") [OPTIONS]

	Play audio tracks from local ~/music/ folder using mpv in tmux sessions.

	OPTIONS:
	  --run     Run in continuous mode (stay open after selection)
	  --help    Show this help message

	BEHAVIOR:
	  - Shows tracks from ~/music/*.mp3
	  - Plays selected track in a tmux session using mpv
	  - Only one track plays at a time (stops others automatically)
	  - In --run mode: shows playing tracks with ► marker
	  - Click playing track again to stop it

	REQUIREMENTS:
	  - tmux, mpv, fzf
	  - Music files in ~/music/
	EOF
	exit 0
fi

# Check for --run flag
RUN_MODE=false
if [[ "$1" == "--run" ]]; then
	RUN_MODE=true
fi

MUSIC_DIR="${HOME}/music"

if [[ ! -d "$MUSIC_DIR" ]]; then
	echo "Error: Music directory not found at $MUSIC_DIR"
	exit 1
fi

# Build track list from local files
# Format: "Clean Title<TAB>Full Path"
track_data=$(find "$MUSIC_DIR" -maxdepth 1 -type f -name "*.mp3" -printf '%f\t%p\n' 2>/dev/null | while IFS=$'\t' read -r filename filepath; do
	# Clean up filename for display: remove .mp3, replace underscores with spaces
	clean_name="${filename%.mp3}"
	clean_name="${clean_name//_/ }"
	echo -e "${clean_name}\t${filepath}"
done | sort)

if [[ -z "$track_data" ]]; then
	echo "Error: No MP3 files found in $MUSIC_DIR"
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

		selected_track_with_number=$(echo "$marked_tracks" | fzf --ansi --reverse --prompt="♪ " --delimiter=$'\t' --with-nth=1 --bind "ctrl-d:half-page-down,ctrl-u:half-page-up")
	else
		selected_track_with_number=$(echo "$track_names_with_numbers" | fzf --reverse --prompt="♪ " --delimiter=$'\t' --with-nth=1 --bind "ctrl-d:half-page-down,ctrl-u:half-page-up")
	fi

	# Extract line (remove number prefix and marker)
	selected_line=$(echo "$selected_track_with_number" | sed 's/^[►[:space:]]*[0-9]\+\.[[:space:]]*//')

	# Format: "Clean Title<TAB>Full Path"
	display_part="${selected_line%%	*}"  # Before TAB (clean title)
	track_path="${selected_line##*	}"    # After TAB (full path)

if [[ -n "$track_path" && -f "$track_path" ]]; then
	song_title="$display_part"

	# Create session name: lowercase, alphanumeric, max 50 chars
	base_session=$(echo "$song_title" | tr -c '[:alnum:]-' '_' | tr '[:upper:]' '[:lower:]' | cut -c 1-45)
	track_hash=$(echo -n "$track_path" | md5sum | cut -c 1-4)
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

		# Create socket directory and path
		socket_dir="${HOME}/.mpv_sockets"
		mkdir -p "$socket_dir"
		socket_path="${socket_dir}/${tmux_session_name}.sock"
		rm -f "$socket_path"

		# Start new tmux session with MPV (local file - simple!)
		tmux new-session -d -s "$tmux_session_name" \
			mpv --loop-file --no-video \
			--input-ipc-server="$socket_path" \
			"$track_path"

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
