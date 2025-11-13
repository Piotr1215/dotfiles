#!/usr/bin/env bash
set -eo pipefail

# Terminal emoji picker using fzf
# Usage: __emoji_picker.sh
# Copies selected emoji to clipboard and outputs to stdout

# Cache file location
readonly CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/emoji-picker"
readonly CACHE_FILE="$CACHE_DIR/emojis.txt"
readonly EMOJI_URL="https://raw.githubusercontent.com/github/gemoji/master/db/emoji.json"

# Ensure cache directory exists
mkdir -p "$CACHE_DIR"

# Function to download and format emoji list
download_emojis() {
    echo "Downloading emoji list..." >&2
    curl -sL "$EMOJI_URL" | \
        jq -r '.[] | select(.emoji) | .emoji + " " + (.description // .aliases[0])' | \
        sort -u > "$CACHE_FILE"
}

# Check if cache file exists and is less than 30 days old
if [[ ! -f "$CACHE_FILE" ]] || [[ $(find "$CACHE_FILE" -mtime +30 2>/dev/null) ]]; then
    download_emojis
fi

# Main function
main() {
    # Check if cache file has content
    if [[ ! -s "$CACHE_FILE" ]]; then
        echo "Error: Emoji cache file is empty. Trying to download..." >&2
        download_emojis
        if [[ ! -s "$CACHE_FILE" ]]; then
            echo "Error: Failed to download emoji list" >&2
            exit 1
        fi
    fi

    # Select emoji with fzf
    local selected
    selected=$(cat "$CACHE_FILE" | fzf \
        --prompt="Emoji: " \
        --height=100% \
        --reverse \
        --no-info \
        --preview-window=hidden \
        --bind='ctrl-c:abort' \
        --header='Select emoji (Ctrl-C to cancel)' \
        --ansi)

    # Exit if nothing selected
    if [[ -z "$selected" ]]; then
        exit 0
    fi

    # Extract just the emoji (first character/field)
    local emoji
    emoji=$(echo "$selected" | awk '{print $1}')

    # Copy to clipboard and paste
    echo -n "$emoji" | xclip -selection clipboard

    # Simulate paste action (Shift+Insert)
    xdotool key --clearmodifiers shift+Insert
}

main "$@"
