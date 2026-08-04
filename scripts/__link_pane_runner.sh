#!/usr/bin/env bash

set -eo pipefail

# Link picker popup. __link_candidates.py emits "display<TAB>command" lines
# from two sources: the curated pet link snippets, and recent browser history.
# fzf shows and searches column one only (--with-nth=1) but hands back the
# whole line, so cut recovers the command with no mapping file in between.

CANDIDATES=/home/decoder/dev/dotfiles/scripts/__link_candidates.py
TEMP_FILE=$(mktemp)

handle_link_selection() {
    "$CANDIDATES" | /usr/local/bin/fzf \
        --delimiter=$'\t' \
        --with-nth=1 \
        --height=100% \
        --layout=reverse \
        --info=inline \
        --border=sharp \
        --header='Bookmarks + history (Ctrl+C to exit)' \
        --prompt='🔍 Search: ' \
        --color='fg:#f8f8f2,bg:#282a36,hl:#bd93f9,fg+:#f8f8f2,bg+:#44475a,hl+:#bd93f9,info:#ffb86c,prompt:#50fa7b,pointer:#ff79c6,marker:#ff79c6,spinner:#ffb86c,header:#6272a4' \
        | cut -f2- > "$TEMP_FILE"
}

export -f handle_link_selection
export CANDIDATES TEMP_FILE

# Open Alacritty with the link selection (centered on screen)
# Calculate center position based on screen resolution
screen_width=$(xdpyinfo | awk '/dimensions:/ {print $2}' | cut -d'x' -f1)
screen_height=$(xdpyinfo | awk '/dimensions:/ {print $2}' | cut -d'x' -f2)
# Assuming ~10 pixels per column and ~20 pixels per line
window_width=$((180 * 10))
window_height=$((50 * 20))
pos_x=$(((screen_width - window_width) / 2))
pos_y=$(((screen_height - window_height) / 2))

alacritty --class bookmarks-popup \
    --config-file /dev/null \
    -o window.dimensions.columns=180 \
    -o window.dimensions.lines=50 \
    -o window.position.x=$pos_x \
    -o window.position.y=$pos_y \
    -e bash -c "handle_link_selection"

# After terminal closes, handle the selection in the parent process
if [[ -f "$TEMP_FILE" ]]; then
    selection=$(cat "$TEMP_FILE")
    rm -f "$TEMP_FILE"

    if [[ -n "$selection" ]]; then
        if [[ "$selection" =~ ^xdg-open ]]; then
            eval "$selection" &
            __focus_browser.sh
        else
            # Copy command to clipboard for pasting elsewhere
            echo -n "$selection" | xclip -selection clipboard
        fi
    fi
fi
