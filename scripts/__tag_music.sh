#!/usr/bin/env bash
set -eo pipefail
IFS=$'\n\t'

# Tag MP3 files based on filename patterns
# Uses mid3v2 from mutagen package

MUSIC_DIR="${HOME}/music"

# Genre keywords mapping (lowercase for matching)
declare -A GENRE_MAP=(
    ["ambient"]="Ambient"
    ["techno"]="Techno"
    ["dark techno"]="Dark Techno"
    ["cyberpunk"]="Cyberpunk"
    ["industrial"]="Industrial"
    ["ebm"]="EBM"
    ["piano"]="Piano"
    ["violin"]="Violin"
    ["cello"]="Cello"
    ["grimdark"]="Grimdark"
    ["drone"]="Drone"
    ["apocalyptic"]="Post-Apocalyptic"
    ["sci fi"]="Sci-Fi"
    ["dark academia"]="Dark Academia"
    ["clubbing"]="Dark Clubbing"
    ["bass"]="Bass"
    ["electronic"]="Electronic"
    ["orchestral"]="Orchestral"
    ["fantasy"]="Fantasy"
    ["lotr"]="Fantasy"
    ["blade runner"]="Cyberpunk"
)

# Known artist patterns (filename pattern -> artist name)
declare -A ARTIST_MAP=(
    ["andrew_chalk"]="Andrew Chalk"
    ["biosphere"]="Biosphere"
    ["william_basinski"]="William Basinski"
    ["vangelis"]="Vangelis"
    ["hans_zimmer"]="Hans Zimmer"
    ["hans zimmer"]="Hans Zimmer"
    ["thomas_koner"]="Thomas Köner"
    ["thomas köner"]="Thomas Köner"
    ["thomaskoner"]="Thomas Köner"
    ["thomasköner"]="Thomas Köner"
    ["johann_johannsson"]="Jóhann Jóhannsson"
    ["lustmord"]="Lustmord"
    ["sleep_research_facility"]="Sleep Research Facility"
    ["sleepresearchfacility"]="Sleep Research Facility"
    ["aleah"]="Aleah"
    ["trees-of-eternity"]="Trees of Eternity"
    ["trees_of_eternity"]="Trees of Eternity"
    ["yob"]="YOB"
    ["jorge"]="Jorge Méndez"
    ["jorgeméndez"]="Jorge Méndez"
    ["max ablitzer"]="Max Ablitzer"
    ["einaudi"]="Ludovico Einaudi"
    ["yiruma"]="Yiruma"
    ["john williams"]="John Williams"
    ["johnwilliams"]="John Williams"
    ["tape_loop_orchestra"]="Tape Loop Orchestra"
    ["royal"]="Royal & the Serpent"
)

detect_genre() {
    local filename_lower="$1"
    local genres=()

    # Check each genre keyword
    for keyword in "${!GENRE_MAP[@]}"; do
        if [[ "$filename_lower" == *"$keyword"* ]]; then
            genres+=("${GENRE_MAP[$keyword]}")
        fi
    done

    # Default genre if none detected
    if [[ ${#genres[@]} -eq 0 ]]; then
        echo "Ambient"
    else
        # Return first 2 genres joined
        printf '%s\n' "${genres[@]}" | head -2 | paste -sd '/' -
    fi
}

detect_artist() {
    local filename_lower="$1"

    # Check known artist patterns
    for pattern in "${!ARTIST_MAP[@]}"; do
        if [[ "$filename_lower" == *"$pattern"* ]]; then
            echo "${ARTIST_MAP[$pattern]}"
            return
        fi
    done

    # Try to extract from "Artist_-_Title" or "Artist - Title" pattern
    if [[ "$filename_lower" =~ ^([^-]+)_-_(.+)$ ]] || [[ "$filename_lower" =~ ^([^-]+)-([^-].+)$ ]]; then
        local potential_artist="${BASH_REMATCH[1]}"
        # Clean up: remove year prefix, underscores to spaces
        potential_artist=$(echo "$potential_artist" | sed 's/^[0-9]*_//' | tr '_' ' ' | sed 's/^ *//' | sed 's/ *$//')
        if [[ -n "$potential_artist" && ${#potential_artist} -gt 2 ]]; then
            echo "$potential_artist"
            return
        fi
    fi

    echo "Unknown Artist"
}

clean_title() {
    local filename="$1"
    local title

    # Remove extension
    title="${filename%.mp3}"

    # Replace underscores with spaces
    title="${title//_/ }"

    # Remove common suffixes
    title=$(echo "$title" | sed -E 's/\s*(Copyright Free|FULL ALBUM|Full Album|STREAM|Official.*Video|HD|1080p|720p|Looped?|1h Loop|Vol\.[0-9]+)//gi')

    # Clean up multiple spaces
    title=$(echo "$title" | tr -s ' ')

    # Trim
    title=$(echo "$title" | sed 's/^ *//' | sed 's/ *$//')

    echo "$title"
}

tag_file() {
    local filepath="$1"
    local filename
    filename=$(basename "$filepath")
    local filename_lower
    filename_lower=$(echo "$filename" | tr '[:upper:]' '[:lower:]')

    local genre artist title
    genre=$(detect_genre "$filename_lower")
    artist=$(detect_artist "$filename_lower")
    title=$(clean_title "$filename")

    echo "Tagging: $filename"
    echo "  Genre:  $genre"
    echo "  Artist: $artist"
    echo "  Title:  $title"

    # Apply tags with mid3v2
    mid3v2 --genre="$genre" --artist="$artist" --song="$title" "$filepath" 2>/dev/null || {
        echo "  WARNING: Failed to tag file"
        return 1
    }

    echo "  OK"
    echo
}

# Main
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    cat <<-EOF
	Usage: $(basename "$0") [FILE...]

	Tag MP3 files based on filename patterns.

	If no files specified, tags all MP3s in ~/music/

	Detects:
	  - Genre keywords (ambient, techno, cyberpunk, etc.)
	  - Known artists (Hans Zimmer, Vangelis, etc.)
	  - Artist from "Artist - Title" filename pattern

	Uses mid3v2 to write ID3 tags.
	EOF
    exit 0
fi

if [[ $# -gt 0 ]]; then
    # Tag specified files
    for file in "$@"; do
        if [[ -f "$file" && "$file" == *.mp3 ]]; then
            tag_file "$file"
        else
            echo "Skipping: $file (not an MP3 file)"
        fi
    done
else
    # Tag all files in music directory
    echo "Tagging all MP3 files in $MUSIC_DIR..."
    echo

    count=0
    while IFS= read -r -d '' file; do
        tag_file "$file"
        ((count++)) || true
    done < <(find "$MUSIC_DIR" -maxdepth 1 -type f -name "*.mp3" -print0)

    echo "Tagged $count files."
fi
