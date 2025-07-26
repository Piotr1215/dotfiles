#!/usr/bin/env bash

set -eo pipefail

# Constants
SESSION_NAME="composite"

# Home path replacer for cleaner display
HOME_REPLACER=""
echo "$HOME" | grep -E "^[a-zA-Z0-9\-_/.@]+$" &>/dev/null
HOME_SED_SAFE=$?
if [ $HOME_SED_SAFE -eq 0 ]; then
    HOME_REPLACER="s|^$HOME/|~/|"
fi

# Check if in tmux first
if [ -z "$TMUX" ]; then
    echo "Error: This script must be run from within a tmux session"
    exit 1
fi

# Create composite session if it doesn't exist
if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    tmux new-session -d -s "$SESSION_NAME" -c "$HOME/dev"
    tmux rename-window -t "$SESSION_NAME:0" "main"
fi

# UI Configuration
BORDER_LABEL=" Compositional Session Builder "
HEADER=" ctrl-f: folders | ctrl-s: pet snippets | ctrl-d: directory"

# Start with pet search as default
RESULT=$(pet search)

if [ -n "$RESULT" ]; then
    # Handle pet snippet result
    WINDOW_NAME="snippet_$(date +%s)"
    tmux new-window -t "$SESSION_NAME" -n "$WINDOW_NAME"
    tmux switch-client -t "$SESSION_NAME:$WINDOW_NAME"
    
    # Check if command has parameters (contains ?)
    if [[ "$RESULT" =~ \? ]]; then
        # Send command without executing, so user can edit parameters
        tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" "$RESULT"
    else
        # Execute command directly
        tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" "$RESULT" C-m
    fi
    exit 0
fi

# If pet search was cancelled, show folder selection
SELECTION=$(
    zoxide query -l | sed -e "$HOME_REPLACER" | \
    fzf --expect=ctrl-f,ctrl-s,ctrl-d \
        --border-label "$BORDER_LABEL" \
        --header "$HEADER" \
        --prompt "folders> "
)

# Parse the output
KEY=$(echo "$SELECTION" | head -1)
RESULT=$(echo "$SELECTION" | tail -n +2)

# Handle different modes based on key pressed
case "$KEY" in
    ctrl-f)
        # Folders mode - already showing folders, just re-run
        exec "$0"
        ;;
    ctrl-s)
        # Pet snippets mode - use pet search directly
        RESULT=$(pet search)
        
        if [ -n "$RESULT" ]; then
            # Create new window for snippet
            WINDOW_NAME="snippet_$(date +%s)"
            tmux new-window -t "$SESSION_NAME" -n "$WINDOW_NAME"
            tmux switch-client -t "$SESSION_NAME:$WINDOW_NAME"
            
            # Check if command has parameters (contains ?)
            if [[ "$RESULT" =~ \? ]]; then
                # Send command without executing, so user can edit parameters
                tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" "$RESULT"
            else
                # Execute command directly
                tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" "$RESULT" C-m
            fi
        fi
        ;;
    ctrl-d)
        # Directory mode
        if fd --version &>/dev/null; then
            RESULT=$(cd $HOME && fd --type d --hidden --absolute-path --color never --exclude .git --exclude node_modules | \
                fzf --border-label "$BORDER_LABEL" \
                    --header " Select a directory" \
                    --prompt "directory> ")
        else
            RESULT=$(cd $HOME && find . -type d -name node_modules -prune -o -name .git -prune -o -type d -print | \
                fzf --border-label "$BORDER_LABEL" \
                    --header " Select a directory" \
                    --prompt "directory> ")
        fi
        
        if [ -n "$RESULT" ]; then
            # Process directory selection same as folder
            REAL_PATH=$(readlink -f "$RESULT")
            FOLDER=$(basename "$REAL_PATH")
            WINDOW_NAME=$(echo "$FOLDER" | tr ' ' '_' | tr '.' '_' | tr ':' '_')
            
            tmux new-window -t "$SESSION_NAME" -n "$WINDOW_NAME" -c "$REAL_PATH"
            tmux switch-client -t "$SESSION_NAME:$WINDOW_NAME"
            
            if [ -d "$REAL_PATH/.git" ]; then
                tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" "git fetch origin --prune" C-m
            fi
        fi
        ;;
    *)
        # Default: folder was selected
        if [ -n "$RESULT" ]; then
            # Convert ~ back to real path
            if [ $HOME_SED_SAFE -eq 0 ]; then
                RESULT=$(echo "$RESULT" | sed -e "s|^~/|$HOME/|")
            fi
            
            # Add to zoxide database
            zoxide add "$RESULT" &>/dev/null
            
            # Resolve symlinks
            REAL_PATH=$(readlink -f "$RESULT")
            
            # Get folder name and create clean window name
            FOLDER=$(basename "$REAL_PATH")
            WINDOW_NAME=$(echo "$FOLDER" | tr ' ' '_' | tr '.' '_' | tr ':' '_')
            
            # Create new window in composite session
            tmux new-window -t "$SESSION_NAME" -n "$WINDOW_NAME" -c "$REAL_PATH"
            
            # Switch to composite session and new window
            tmux switch-client -t "$SESSION_NAME:$WINDOW_NAME"
            
            # If it's a git repo, fetch updates
            if [ -d "$REAL_PATH/.git" ]; then
                tmux send-keys -t "$SESSION_NAME:$WINDOW_NAME" "git fetch origin --prune" C-m
            fi
        fi
        ;;
esac