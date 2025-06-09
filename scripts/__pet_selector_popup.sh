#!/usr/bin/env bash
set -eo pipefail

# Global pet snippet selector popup
# Opens pet search in a centered popup terminal

# Create temp file for communication between processes
TEMP_FILE=$(mktemp)

# Function to handle pet selection with the same logic as zsh function
handle_pet_selection() {
    local selection=$(pet search --query "Link to ")
    # Write the selection to temp file for parent process to handle
    echo "$selection" > "$TEMP_FILE"
}

# Export the function so it's available in the new shell
export -f handle_pet_selection
export TEMP_FILE

# Open popup terminal and run the function
# Calculate center position for 3840x2160 screen
# Estimate terminal size: 130 cols * 8px ≈ 1040px width, 50 lines * 16px ≈ 800px height
alacritty --class pet-popup \
    --config-file /dev/null \
    -o window.dimensions.columns=130 \
    -o window.dimensions.lines=50 \
    -o window.position.x=1400 \
    -o window.position.y=580 \
    -e bash -c "handle_pet_selection"

# After terminal closes, handle the selection in the parent process
if [[ -f "$TEMP_FILE" ]]; then
    selection=$(cat "$TEMP_FILE")
    rm -f "$TEMP_FILE"
    
    if [[ "$selection" =~ ^"xdg-open" ]]; then
        eval "$selection" &
    else
        # Copy command to clipboard for pasting elsewhere
        echo -n "$selection" | xclip -selection clipboard
    fi
fi
