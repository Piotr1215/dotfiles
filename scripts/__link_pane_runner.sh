#!/usr/bin/env bash

set -eo pipefail

# Create temp file for communication between processes
TEMP_FILE=$(mktemp)

# Function to handle link selection
handle_link_selection() {
    # Create a temporary directory for our fzf wrapper
    WRAPPER_DIR=$(mktemp -d)

    # Create an fzf wrapper that transforms link display
    cat > "$WRAPPER_DIR/fzf" << 'EOF'
#!/usr/bin/env bash
# Create a temporary file to store the mapping
MAPFILE=$(mktemp)

# Read stdin, create mapping, and show cleaned version with URL
while IFS= read -r line; do
    # Extract the clean display name - text between "Link to " and "]:"
    clean_name=$(echo "$line" | sed -n 's/.*\[Link to \([^]]*\)\].*/\1/p')
    # Extract the URL - text between 'xdg-open "' and '"' (or before space/hashtag)
    url=$(echo "$line" | sed -n 's/.*xdg-open \+"\?\([^" ]*\).*/\1/p')
    # Truncate name if too long (max 65 chars to leave room for brackets and ellipsis)
    if [ ${#clean_name} -gt 65 ]; then
        clean_name="${clean_name:0:65}..."
    fi
    # Create display line with name and URL in two columns
    display_line=$(printf "%-70s  %s" "[$clean_name]" "$url")
    # Store mapping of display line to original
    echo "$display_line|$line" >> "$MAPFILE"
    # Output display line for fzf
    echo "$display_line"
done | sort | /usr/local/bin/fzf \
    --height=100% \
    --layout=reverse \
    --info=inline \
    --border=sharp \
    --header='Bookmarks (Ctrl+C to exit)' \
    --prompt='🔍 Search: ' \
    --color='fg:#f8f8f2,bg:#282a36,hl:#bd93f9,fg+:#f8f8f2,bg+:#44475a,hl+:#bd93f9,info:#ffb86c,prompt:#50fa7b,pointer:#ff79c6,marker:#ff79c6,spinner:#ffb86c,header:#6272a4' \
    "$@" | {
    # Read the selected clean line
    if IFS= read -r selected; then
        # Find the original line from our mapping
        grep -F "$selected|" "$MAPFILE" | cut -d'|' -f2-
    fi
}

# Clean up mapping file
rm -f "$MAPFILE"
EOF

    chmod +x "$WRAPPER_DIR/fzf"

    # Add our wrapper to PATH before the real fzf
    export PATH="$WRAPPER_DIR:$PATH"

    # Use pet to search only link snippets file
    RESULT=$(PET_SNIPPET_FILE=/home/decoder/dev/pet-snippets/pet-links.toml pet search)

    # Clean up
    rm -rf "$WRAPPER_DIR"

    # Write the selection to temp file for parent process to handle
    echo "$RESULT" > "$TEMP_FILE"
}

export -f handle_link_selection
export TEMP_FILE

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
            wmctrl -a Firefox
        else
            # Copy command to clipboard for pasting elsewhere
            echo -n "$selection" | xclip -selection clipboard
        fi
    fi
fi