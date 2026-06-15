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

	FAVOURITES:
	  - Press ctrl-f in the picker to toggle ★ favourite on the highlighted track
	  - Press ctrl-s to filter the list to favourites only (press again for all)
	  - Favourites show a ★ marker and sort to the top
	  - Stored as filenames in ~/music/.favourites

	REQUIREMENTS:
	  - tmux, mpv, fzf
	  - Music files in ~/music/
	EOF
	exit 0
fi

# Music dir is overridable (env) to keep the script testable
: "${MUSIC_DIR:=${HOME}/music}"
FAV_FILE="${MUSIC_DIR}/.favourites"
# Presence of this flag = picker is currently filtered to favourites only
FILTER_FLAG="/tmp/pt_fav_filter"

# Render the numbered, marked, sorted track list.
# Output line format: "<play><fav> NN. Clean Title<TAB>Full Path"
#   play = ► if currently playing (run mode) else space
#   fav  = ★ if favourite else space
# Favourites sort to the top; in run mode the playing track floats above all.
render_list() {
	local run_mode="$1"

	# Currently playing track display name (run mode only)
	local current_display=""
	if [[ "$run_mode" == true ]]; then
		local session_file="/tmp/current_music_session.txt"
		local display_file="/tmp/current_music_session_display.txt"
		if [[ -f "$session_file" && -f "$display_file" ]]; then
			local session_name
			session_name=$(cat "$session_file" 2>/dev/null)
			if tmux has-session -t "$session_name" 2>/dev/null; then
				current_display=$(cat "$display_file" 2>/dev/null)
			fi
		fi
	fi

	# Build rows: "fav_flag<TAB>clean_name<TAB>filepath", then sort favourites first
	local rows
	rows=$(find "$MUSIC_DIR" -maxdepth 1 -type f -name "*.mp3" -printf '%f\t%p\n' 2>/dev/null | while IFS=$'\t' read -r filename filepath; do
		local clean_name="${filename%.mp3}"
		clean_name="${clean_name//_/ }"
		local fav=0
		if [[ -f "$FAV_FILE" ]] && grep -qxF "$filename" "$FAV_FILE"; then
			fav=1
		fi
		printf '%d\t%s\t%s\n' "$fav" "$clean_name" "$filepath"
	done | sort -t$'\t' -k1,1r -k2,2)

	# Favourites-only view when the filter flag is set
	if [[ -f "$FILTER_FLAG" ]]; then
		rows=$(printf '%s\n' "$rows" | awk -F'\t' '$1 == "1"')
	fi

	[[ -z "$rows" ]] && return 0

	# Number rows and attach markers (plain text so fzf's returned line
	# stays free of ANSI codes the selection parser would have to strip)
	local marked
	marked=$(printf '%s\n' "$rows" | awk -F'\t' -v playing="$current_display" '
	{
		play = ($2 == playing) ? "►" : " "
		fav  = ($1 == "1") ? "★" : " "
		printf "%s%s %02d. %s\t%s\n", play, fav, NR, $2, $3
	}')

	# In run mode, float the playing track to the very top
	if [[ "$run_mode" == true ]]; then
		local playing rest
		playing=$(grep '^►' <<<"$marked" || true)
		rest=$(grep -v '^►' <<<"$marked" || true)
		[[ -n "$playing" ]] && marked="${playing}"$'\n'"${rest}"
	fi

	printf '%s\n' "$marked"
}

# Toggle favourite status for the track on the given picker line.
toggle_fav() {
	local line="$1"
	local path="${line##*$'\t'}"
	local base
	base=$(basename "$path")
	touch "$FAV_FILE"
	if grep -qxF "$base" "$FAV_FILE"; then
		{ grep -vxF "$base" "$FAV_FILE" || true; } >"${FAV_FILE}.tmp"
		mv "${FAV_FILE}.tmp" "$FAV_FILE"
	else
		printf '%s\n' "$base" >>"$FAV_FILE"
	fi
}

# Toggle the favourites-only filter flag.
toggle_filter() {
	if [[ -f "$FILTER_FLAG" ]]; then
		rm -f "$FILTER_FLAG"
	else
		touch "$FILTER_FLAG"
	fi
}

# Hidden subcommands invoked by fzf bindings (reload/toggle)
case "$1" in
	__render) render_list "$2"; exit 0 ;;
	__togglefav) toggle_fav "$2"; exit 0 ;;
	__togglefilter) toggle_filter; exit 0 ;;
esac

# Check for --run flag
RUN_MODE=false
if [[ "$1" == "--run" ]]; then
	RUN_MODE=true
fi

if [[ ! -d "$MUSIC_DIR" ]]; then
	echo "Error: Music directory not found at $MUSIC_DIR"
	exit 1
fi

SELF="$(readlink -f "$0")"

# Each fresh launch starts showing all tracks, not a stale favourites filter
rm -f "$FILTER_FLAG"

# Main loop
while true; do
	list=$(render_list "$RUN_MODE")
	if [[ -z "$list" ]]; then
		echo "Error: No MP3 files found in $MUSIC_DIR"
		exit 1
	fi

	selected_track_with_number=$(echo "$list" | fzf --ansi --reverse --prompt="♪ " \
		--delimiter=$'\t' --with-nth=1 \
		--header="ctrl-f: toggle ★   ctrl-s: favourites only" \
		--bind "ctrl-d:half-page-down,ctrl-u:half-page-up" \
		--bind "ctrl-f:execute-silent(${SELF} __togglefav {})+reload(${SELF} __render ${RUN_MODE})" \
		--bind "ctrl-s:execute-silent(${SELF} __togglefilter)+reload(${SELF} __render ${RUN_MODE})") || true

	# Extract line (strip play/fav markers and number prefix)
	selected_line=$(echo "$selected_track_with_number" | sed -E 's/^[►★[:space:]]*[0-9]+\.[[:space:]]*//')

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
