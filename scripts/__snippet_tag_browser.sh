#!/usr/bin/env bash

set -eo pipefail

# Check if in tmux first
if [ -z "$TMUX" ]; then
    echo "Error: This script must be run from within a tmux session"
    exit 1
fi

# Get current directory
CURRENT_DIR=$(tmux display-message -p '#{pane_current_path}')

# Get all tags with counts
TAGS=$(pet list | awk -F'Tag:[[:space:]]*' '
NF>1 && $2!="" {
    n=split($2,parts,/[ ,]+/); 
    for(i=1;i<=n;i++) 
        if(parts[i]!="" && parts[i]!~/^-+$/) 
            count[parts[i]]++
} 
END {
    for(tag in count) 
        printf "%-30s [%d]\n", tag, count[tag]
}' | sort)

# Let user select a tag
SELECTED=$(echo "$TAGS" | fzf --prompt="Select tag: " --header="Press Enter to view snippets for this tag")

if [ -n "$SELECTED" ]; then
    # Extract just the tag name
    TAG=$(echo "$SELECTED" | awk '{print $1}')
    
    # Create a temporary directory for our fzf wrapper
    WRAPPER_DIR=$(mktemp -d)
    
    # Create an fzf wrapper that filters out links
    cat > "$WRAPPER_DIR/fzf" << 'EOF'
#!/usr/bin/env bash
# Simply filter out lines starting with [Link to before passing to real fzf
grep -v '^\[Link to' | /usr/local/bin/fzf "$@"
EOF
    
    chmod +x "$WRAPPER_DIR/fzf"
    
    # Add our wrapper to PATH before the real fzf
    export PATH="$WRAPPER_DIR:$PATH"
    
    # Now search for snippets with the selected tag
    RESULT=$(pet search -t "$TAG")
    
    # Clean up
    rm -rf "$WRAPPER_DIR"
    
    if [ -n "$RESULT" ]; then
        # Check if the command starts with xdg-open
        if [[ "$RESULT" =~ ^xdg-open[[:space:]] ]]; then
            # Use tmux run-shell to execute in proper environment
            tmux run-shell "$RESULT && wmctrl -a Firefox"
            exit 0
        else
            # Create a new vertical split pane for other commands
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
fi