#!/usr/bin/env bash

set -eo pipefail

# Check if in tmux first
if [ -z "$TMUX" ]; then
    echo "Error: This script must be run from within a tmux session"
    exit 1
fi

# Get current directory
CURRENT_DIR=$(tmux display-message -p '#{pane_current_path}')

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
done | sort | /usr/local/bin/fzf "$@" | {
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

if [ -n "$RESULT" ]; then
    # Links should always be xdg-open commands, but let's check anyway
    if [[ "$RESULT" =~ ^xdg-open[[:space:]] ]]; then
        # Use tmux run-shell to execute in proper environment
        tmux run-shell "$RESULT && wmctrl -a Firefox"
        exit 0
    else
        # Just in case it's not xdg-open, handle it normally
        # Create a new vertical split pane
        tmux split-window -v -c "$CURRENT_DIR"
        
        # Get the new pane ID
        NEW_PANE=$(tmux display-message -p '#{pane_id}')
        
        # Clear the new pane
        tmux send-keys -t "$NEW_PANE" "clear" C-m
        
        # Check if command has parameters (contains ?)
        if [[ "$RESULT" =~ \? ]]; then
            # Send command without executing, so user can edit parameters
            tmux send-keys -t "$NEW_PANE" "$RESULT"
        else
            # Execute command directly
            tmux send-keys -t "$NEW_PANE" "$RESULT" C-m
        fi
        
        # Focus on the new pane
        tmux select-pane -t "$NEW_PANE"
    fi
fi