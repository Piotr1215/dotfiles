#!/usr/bin/env bash

# Source generic error handling function
source __trap.sh

set -eo pipefail

# Set new line and tab for word splitting
IFS=$'\n\t'

# Help function
help_function() {
    echo "Usage: __path_to_clipboard.sh [OPTIONS]"
    echo ""
    echo "Open files in neovim or copy paths to clipboard"
    echo ""
    echo "Options:"
    echo "  -h, --help       Show this help message"
    echo "  -d, --dirs-only  Show only directories"
    echo "  -f, --files-only Show only files"
    echo "  -a, --all        Include hidden files/directories"
    echo ""
    echo "Keybindings in fzf:"
    echo "  Enter     Open in neovim"
    echo "  Ctrl+Y    Copy path to clipboard"
    echo "  Ctrl+X    Switch to zoxide"
    echo "  Ctrl+R    Switch to current directory"
    echo "  Ctrl+D    Switch to all directories"
    echo "  Ctrl+F    Switch to all files"
    echo "  Ctrl+C    Cancel"
    echo "  Tab       Multi-select"
}

# Parse arguments
# Default to HOME directory for better coverage
SEARCH_DIR="$HOME"
FIND_TYPE=""
HIDDEN=""
MAX_DEPTH="--max-depth 4"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            help_function
            exit 0
            ;;
        -d|--dirs-only)
            FIND_TYPE="--type d"
            shift
            ;;
        -f|--files-only)
            FIND_TYPE="--type f"
            shift
            ;;
        -c|--current)
            SEARCH_DIR="."
            shift
            ;;
        -a|--all)
            HIDDEN="-H"
            shift
            ;;
        --deep)
            MAX_DEPTH=""
            shift
            ;;
        *)
            echo "Unknown option: $1"
            help_function
            exit 1
            ;;
    esac
done

# Function to copy paths to clipboard
copy_to_clipboard() {
    local mode="$1"
    shift
    local paths=("$@")
    local output=""
    
    for path in "${paths[@]}"; do
        case "$mode" in
            absolute)
                output+="$(realpath "$path")"$'\n'
                ;;
            relative)
                output+="$(realpath --relative-to="$PWD" "$path")"$'\n'
                ;;
            basename)
                output+="$(basename "$path")"$'\n'
                ;;
            dirname)
                if [[ -f "$path" ]]; then
                    output+="$(dirname "$(realpath "$path")")"$'\n'
                else
                    output+="$(realpath "$path")"$'\n'
                fi
                ;;
        esac
    done
    
    # Remove trailing newline and copy to clipboard
    echo -n "${output%$'\n'}" | xclip -selection clipboard
    
    # Show notification
    local count="${#paths[@]}"
    local plural=""
    [[ $count -gt 1 ]] && plural="s"
    echo "✓ Copied $count path$plural to clipboard ($mode)"
}

# Create preview command based on type
if [[ -n "$FIND_TYPE" ]] && [[ "$FIND_TYPE" == "--type d" ]]; then
    PREVIEW_CMD='exa --color=always --long --all --header --icons --git {} 2>/dev/null || ls -la {}'
else
    PREVIEW_CMD='[[ -d {} ]] && (exa --color=always --long --all --header --icons --git {} 2>/dev/null || ls -la {}) || (bat --color=always {} 2>/dev/null || cat {})'
fi

# Define keybindings for switching sources (only the useful filters)
ZOXIDE_BIND="ctrl-x:change-prompt(zoxide> )+reload(zoxide query -l)"
CURRENT_BIND="ctrl-r:change-prompt(current> )+reload(fd $HIDDEN $FIND_TYPE --max-depth 2 . '$(pwd)')"
DIR_BIND="ctrl-d:change-prompt(directories> )+reload(cd $HOME && fd --type d --hidden --absolute-path --color never --exclude .git --exclude node_modules --exclude .cache --max-depth 4)"
# Files sorted by zoxide directories
FILE_BIND="ctrl-f:change-prompt(files> )+reload(bash -c '{ zoxide query -l | while read -r dir; do fd --type f --hidden --absolute-path --color never --exclude .git --exclude node_modules --exclude .cache --max-depth 2 . \"\$dir\" 2>/dev/null | head -20; done; fd --type f --hidden --absolute-path --color never --exclude .git --exclude node_modules --exclude .cache --max-depth 3 . \"$HOME\" 2>/dev/null; } | awk \"!seen[\\\$0]++\"')"

# Start with zoxide dirs + all files - best of both worlds
OUTPUT=$( {
    # First show zoxide directories (most frequently used)
    zoxide query -l
    # Then show all files from home, excluding cache directory
    fd --type f --hidden --absolute-path --color never --exclude .git --exclude node_modules --exclude .cache --max-depth 4 . "$HOME"
} | fzf \
    --multi \
    --preview '[[ -d {} ]] && (exa --color=always --long --all --header --icons --git {} 2>/dev/null || ls -la {}) || [[ -f {} ]] && (bat --color=always {} 2>/dev/null || cat {}) || echo "Preview not available"' \
    --preview-window 'right:50%:wrap' \
    --header ' Enter: open | C-o: split | C-y: copy | C-f: files | C-x: zoxide | C-r: current | C-d: dirs' \
    --prompt 'all> ' \
    --bind "$ZOXIDE_BIND" \
    --bind "$CURRENT_BIND" \
    --bind "$DIR_BIND" \
    --bind "$FILE_BIND" \
    --bind "ctrl-c:abort" \
    --expect=ctrl-y,ctrl-o)

# Parse output - first line is the key pressed, rest are selections
KEY=$(echo "$OUTPUT" | head -1)
# Get selections (skip first line which is the key)
SELECTIONS=$(echo "$OUTPUT" | tail -n +2)

if [ -n "$SELECTIONS" ]; then
    # Process selections based on key pressed
    if [ "$KEY" = "ctrl-y" ]; then
        # Copy paths to clipboard (use printf to avoid trailing newline)
        result=""
        while IFS= read -r path; do
            if [ -n "$path" ]; then
                expanded_path="${path/#\~/$HOME}"
                real_path=$(realpath "$expanded_path" 2>/dev/null || echo "$expanded_path")
                if [ -z "$result" ]; then
                    result="$real_path"
                else
                    result="$result"$'\n'"$real_path"
                fi
            fi
        done <<< "$SELECTIONS"
        
        # Use printf to avoid adding newline
        printf "%s" "$result" | xclip -selection clipboard
        
        count=$(echo "$SELECTIONS" | wc -l)
        plural=""
        [[ $count -gt 1 ]] && plural="s"
        echo "✓ Copied $count path$plural to clipboard"
    elif [ "$KEY" = "ctrl-o" ]; then
        # Open in split pane
        # Build array of files
        declare -a file_array
        while IFS= read -r path; do
            if [ -n "$path" ]; then
                expanded_path="${path/#\~/$HOME}"
                real_path=$(realpath "$expanded_path" 2>/dev/null || echo "$expanded_path")
                file_array+=("$real_path")
            fi
        done <<< "$SELECTIONS"
        
        if [ ${#file_array[@]} -gt 0 ]; then
            first_file="${file_array[0]}"
            
            if [ -d "$first_file" ]; then
                # If it's a directory, create new window in current session
                window_name=$(basename "$first_file")
                tmux new-window -n "$window_name" -c "$first_file"
            else
                # If it's file(s), open in editor in split pane
                dir_path=$(dirname "$first_file")
                tmux split-window -h -c "$dir_path" nvim "${file_array[@]}"
            fi
        fi
    else
        # Default action: Open in new tmux window
        # Build array of files
        declare -a file_array
        while IFS= read -r path; do
            if [ -n "$path" ]; then
                expanded_path="${path/#\~/$HOME}"
                real_path=$(realpath "$expanded_path" 2>/dev/null || echo "$expanded_path")
                file_array+=("$real_path")
            fi
        done <<< "$SELECTIONS"
        
        if [ ${#file_array[@]} -gt 0 ]; then
            first_file="${file_array[0]}"
            
            if [ -d "$first_file" ]; then
                # If it's a directory, use sessionizer to create/switch to session
                ~/dev/dotfiles/scripts/__sessionizer.sh "$first_file"
            else
                # If it's file(s), open in editor
                dir_path=$(dirname "$first_file")
                window_name=$(basename "$first_file")
                # Pass files as arguments to nvim
                tmux new-window -n "$window_name" -c "$dir_path" nvim "${file_array[@]}"
            fi
        fi
    fi
fi