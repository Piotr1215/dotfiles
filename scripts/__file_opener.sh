#!/usr/bin/env bash

# Source generic error handling function
source __trap.sh

set -eo pipefail

# Set PATH to include user binaries (tmux popup has minimal PATH)
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/go/bin:$PATH"


# Detect if running in tmux popup and adjust terminal settings
if [[ -n "$TMUX" ]] && [[ "$TERM" == "tmux-256color" || "$TERM" == "screen-256color" ]]; then
    # Suppress error output for terminal control sequences
    export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS --no-mouse"
    # Clear any terminal errors before starting
    clear 2>/dev/null || true
fi

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
    echo "  Ctrl+D    Switch to all directories"
    echo "  Ctrl+F    Switch to all files"
    echo "  Ctrl+B    Switch to bookmarks"
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
DIR_BIND="ctrl-d:change-prompt(directories> )+reload(cd $HOME && fd --type d --hidden --absolute-path --color never --exclude .git --exclude node_modules --exclude .cache --max-depth 4)"
# Files sorted by zoxide directories
FILE_BIND="ctrl-f:change-prompt(files> )+reload(bash -c '{ zoxide query -l | while read -r dir; do fd --type f --hidden --absolute-path --color never --exclude .git --exclude node_modules --exclude .cache --max-depth 2 . \"\$dir\" 2>/dev/null | head -20; done; fd --type f --hidden --absolute-path --color never --exclude .git --exclude node_modules --exclude .cache --max-depth 3 . \"$HOME\" 2>/dev/null; } | awk \"!seen[\\\$0]++\"')"
# Bookmarks binding - extract and expand paths from bookmarks.conf with descriptions
BOOKMARKS_BIND="ctrl-b:change-prompt(bookmarks> )+reload(bash -c 'while IFS=\";\" read -r desc path; do path=\${path/#\\~/\$HOME}; printf \"%-60s %s\\n\" \"\$desc\" \"\$path\"; done < ~/dev/dotfiles/scripts/__bookmarks.conf')"

# Marker file for returning to main picker
RETURN_MARKER="/tmp/file_opener_return_$$"

# PRs binding (Ctrl+G for GitHub) - sets marker, launches PR script, then aborts to restart loop
PR_BIND="ctrl-g:execute-silent(touch $RETURN_MARKER)+execute(~/dev/dotfiles/scripts/__my_prs.sh fzf)+abort"

# Linear issues binding (Ctrl+I for Issues) - sets marker, launches Linear script, then aborts to restart loop
LINEAR_BIND="ctrl-i:execute-silent(touch $RETURN_MARKER)+execute(~/dev/dotfiles/scripts/__linear_issue_viewer.sh)+abort"

# Edit tmuxinator config (Ctrl+E) - only works on sessions
EDIT_BIND="ctrl-e:execute(name={} && name=\${name% *} && [[ -f ~/.config/tmuxinator/\${name}.yml ]] && nvim ~/.config/tmuxinator/\${name}.yml)+abort"

# Music picker (Ctrl+U) - run music picker, closes popup on exit (can't use Ctrl+M, it's Enter)
MUSIC_BIND="ctrl-u:execute(~/dev/dotfiles/scripts/__play_track.sh --run)+abort"

# Kill current music (Ctrl+K)
KILL_MUSIC_BIND="ctrl-k:execute-silent(session=\$(cat /tmp/current_music_session.txt 2>/dev/null) && tmux kill-session -t \"\$session\" 2>/dev/null && rm -f /tmp/current_music_session.txt /tmp/current_music_session_display.txt)"

# Copy to clipboard binding - extracts path from bookmark format or uses line as-is
COPY_BIND="ctrl-y:execute-silent(~/dev/dotfiles/scripts/__copy_path_with_notification.sh {})+abort"

# Loop to allow returning from PRs/Linear back to main picker
while true; do
    OUTPUT=$( {
        # All tmuxinator sessions (* = active), task first
        active=$(tmux ls -F '#{session_name}' 2>/dev/null | tr '\n' '|')
        for s in task $(ls ~/.config/tmuxinator/*.yml 2>/dev/null | xargs -n1 basename | sed 's/\.yml$//' | grep -v '^task$' | sort); do
            [[ "|$active" == *"|$s|"* || "$active" == "$s|"* ]] && echo "$s *" || echo "$s"
        done
        # First show zoxide directories (most frequently used)
        zoxide query -l
        # Then show all files from home, excluding cache directory
        fd --type f --hidden --absolute-path --color never --exclude .git --exclude node_modules --exclude .cache --max-depth 4 . "$HOME"
    } | fzf \
        --multi \
        --tiebreak=index \
        --preview 'item={}; name=${item% \*};
            if [[ -f ~/.config/tmuxinator/${name}.yml ]]; then
                [[ "$item" == *" *" ]] && echo "=== ACTIVE ===" && tmux list-windows -t "$name" -F "  #I: #W (#P panes)" 2>/dev/null && echo ""
                bat --color=always ~/.config/tmuxinator/${name}.yml 2>/dev/null || cat ~/.config/tmuxinator/${name}.yml
            elif [[ -d "$item" ]]; then
                exa --color=always --long --all --header --icons --git "$item" 2>/dev/null || ls -la "$item"
            elif [[ -f "$item" ]]; then
                bat --color=always "$item" 2>/dev/null || cat "$item"
            else
                echo "Preview not available"
            fi' \
        --preview-window 'right:50%:wrap' \
        --header ' C-f:files C-x:zoxide C-d:dirs C-b:bookmarks C-g:PRs C-i:Linear C-e:edit C-u:music C-k:stop | C-y:copy' \
        --prompt 'all> ' \
        --bind "$ZOXIDE_BIND" \
        --bind "$DIR_BIND" \
        --bind "$FILE_BIND" \
        --bind "$BOOKMARKS_BIND" \
        --bind "$PR_BIND" \
        --bind "$LINEAR_BIND" \
        --bind "$EDIT_BIND" \
        --bind "$MUSIC_BIND" \
        --bind "$KILL_MUSIC_BIND" \
        --bind "$COPY_BIND" \
        --bind "ctrl-c:abort" \
        2>/dev/null) || true

    # Check if we should return to main picker (marker exists from PRs/Linear)
    if [[ -f "$RETURN_MARKER" ]]; then
        rm -f "$RETURN_MARKER"
        continue  # Restart the loop, show main picker again
    fi

    # Otherwise, exit the loop (Ctrl+C on main or selection made)
    break
done

# Process selections (ctrl-y is now handled by fzf binding)
if [ -n "$OUTPUT" ]; then
    # Handle sessions (format: "name" or "name *")
    if [[ "$OUTPUT" =~ ^([a-z0-9-]+)( \*)?$ ]]; then
        session="${BASH_REMATCH[1]}"
        if [[ -f ~/.config/tmuxinator/${session}.yml ]]; then
            tmux switch-client -t "$session" 2>/dev/null || tmuxinator start "$session"
            exit 0
        fi
    fi

    # Build array of files from selections
    declare -a file_array
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            real_path=$(~/dev/dotfiles/scripts/__extract_path_from_fzf.sh "$line")
            file_array+=("$real_path")
        fi
    done <<< "$OUTPUT"

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

# Exit cleanly
exit 0