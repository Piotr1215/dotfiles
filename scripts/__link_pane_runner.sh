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

# Read stdin, filter for links, create mapping, and show cleaned version
while IFS= read -r line; do
    if [[ "$line" =~ ^\[Link\ to ]]; then
        # Extract the clean display name - keep only text between brackets
        clean_line=$(echo "$line" | sed 's/^\[Link to \(.*\)\].*/[\1]/')
        # Store mapping of clean line to original
        echo "$clean_line|$line" >> "$MAPFILE"
        # Output clean line for fzf
        echo "$clean_line"
    fi
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

    # Use pet to search - our wrapper will filter for links only
    RESULT=$(pet search)

    # Clean up
    rm -rf "$WRAPPER_DIR"

    # Write the selection to temp file for parent process to handle
    echo "$RESULT" > "$TEMP_FILE"
}

export -f handle_link_selection
export TEMP_FILE

# Open Alacritty with the link selection
alacritty --class bookmarks-popup \
    --config-file /dev/null \
    -o window.dimensions.columns=120 \
    -o window.dimensions.lines=40 \
    -o window.position.x=1440 \
    -o window.position.y=660 \
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