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
    echo "  Ctrl+B    GitHub repo search"
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
# Ctrl+X returns to main view (all sources: sessions + zoxide + files)
HOME_BIND="ctrl-x:change-prompt(all> )+reload(active=\$(tmux ls -F '#{session_name}' 2>/dev/null); active_pipe=\$(echo \"\$active\" | tr '\\n' '|'); configs=\$(ls --color=never ~/.config/tmuxinator/*.yml 2>/dev/null | xargs -n1 basename | sed 's/\\.yml\$//' | sort); echo \"\$active\" | while read -r s; do [[ -n \"\$s\" ]] && echo \"\$s ◀◀◀\"; done; echo \"\$configs\" | while read -r s; do [[ -n \"\$s\" && \"|\$active_pipe\" != *\"|\$s|\"* && \"\$active_pipe\" != \"\$s|\"* ]] && echo \"\$s\"; done; zoxide query -l; cache=/tmp/file_opener_cache_\$USER; if [[ -f \$cache ]] && [[ \$(((\$(date +%s) - \$(stat -c %Y \$cache)))) -lt 60 ]]; then cat \$cache; else fd --type f --hidden --absolute-path --color never --exclude .git --exclude node_modules --exclude .cache --exclude image-cache --exclude plugins --exclude stats-cache.json --changed-within 7d . ~/dev ~/loft ~/.config/nvim ~/.claude 2>/dev/null | xargs stat --format '%Y %n' 2>/dev/null | sort -rn | cut -d' ' -f2- | tee \$cache; fi)"
# Files from work directories
FILE_BIND="ctrl-f:change-prompt(files> )+reload(cache=/tmp/file_opener_cache_\$USER; if [[ -f \$cache ]] && [[ \$(((\$(date +%s) - \$(stat -c %Y \$cache)))) -lt 60 ]]; then cat \$cache; else fd --type f --hidden --absolute-path --color never --exclude .git --exclude node_modules --exclude .cache --exclude image-cache --exclude plugins --exclude stats-cache.json --changed-within 7d . ~/dev ~/loft ~/.config/nvim ~/.claude 2>/dev/null | xargs stat --format '%Y %n' 2>/dev/null | sort -rn | cut -d' ' -f2- | tee \$cache; fi)"
# GitHub repo search binding - search, clone/cd into repo
GITHUB_BIND="ctrl-b:execute-silent(touch $RETURN_MARKER)+execute(~/dev/dotfiles/scripts/__github_search.sh)+abort"

# Marker file for returning to main picker
RETURN_MARKER="/tmp/file_opener_return_$$"

# PRs binding (Ctrl+G for GitHub) - sets marker, launches PR script, then aborts to restart loop
PR_BIND="ctrl-g:execute-silent(touch $RETURN_MARKER)+execute(~/dev/dotfiles/scripts/__my_prs.sh fzf)+abort"

# Linear issues binding (Ctrl+I for Issues) - sets marker, launches Linear script, then aborts to restart loop
LINEAR_BIND="ctrl-i:execute-silent(touch $RETURN_MARKER)+execute(~/dev/dotfiles/scripts/__linear_issue_viewer.sh)+abort"

# Edit tmuxinator config (Ctrl+E) - only works on sessions
EDIT_BIND="ctrl-e:execute(name={}; name=\${name% ◀◀◀}; [[ -f ~/.config/tmuxinator/\${name}.yml ]] && nvim ~/.config/tmuxinator/\${name}.yml)+abort"

# Music picker (Ctrl+U) - run music picker, closes popup on exit (can't use Ctrl+M, it's Enter)
MUSIC_BIND="ctrl-u:execute(~/dev/dotfiles/scripts/__play_track.sh --run)+abort"

# Kill selected session (Ctrl+K) - switches away if current, then kills
KILL_SESSION_BIND="ctrl-k:execute(name={}; name=\${name% ◀◀◀}; cur=\$(tmux display-message -p '#S'); [[ \"\$name\" == \"\$cur\" ]] && { tmux switch-client -l 2>/dev/null || tmux switch-client -n 2>/dev/null; }; tmux kill-session -t \"\$name\" 2>/dev/null)+abort"

# Copy to clipboard binding - extracts path from bookmark format or uses line as-is
COPY_BIND="ctrl-y:execute-silent(~/dev/dotfiles/scripts/__copy_path_with_notification.sh {})+abort"

# Loop to allow returning from PRs/Linear back to main picker
while true; do
    OUTPUT=$( {
        # Sessions: ALL active first (bottom in fzf), then inactive configs
        active_sessions=$(tmux ls -F '#{session_name}' 2>/dev/null)
        active_pipe=$(echo "$active_sessions" | tr '\n' '|')
        configs=$(ls --color=never ~/.config/tmuxinator/*.yml 2>/dev/null | xargs -n1 basename | sed 's/\.yml$//' | sort)
        # All active sessions with marker
        echo "$active_sessions" | while read -r s; do
            [[ -n "$s" ]] && echo "$s ◀◀◀"
        done
        # Inactive tmuxinator configs without marker
        echo "$configs" | while read -r s; do
            [[ -n "$s" && "|$active_pipe" != *"|$s|"* && "$active_pipe" != "$s|"* ]] && echo "$s"
        done
        # Zoxide directories (most frequently used) - already sorted by frecency
        zoxide query -l
        # Files from work directories - use cache if fresh (<60s old), else regenerate
        cache_file="/tmp/file_opener_cache_$USER"
        if [[ -f "$cache_file" ]] && [[ $(($(date +%s) - $(stat -c %Y "$cache_file"))) -lt 60 ]]; then
            cat "$cache_file"
        else
            fd --type f --hidden --absolute-path --color never --exclude .git --exclude node_modules --exclude .cache --exclude image-cache --exclude plugins --exclude stats-cache.json --changed-within 7d . ~/dev ~/loft ~/.config/nvim ~/.claude 2>/dev/null | xargs stat --format '%Y %n' 2>/dev/null | sort -rn | cut -d' ' -f2- | tee "$cache_file"
        fi
    } | fzf \
        --multi \
        --tiebreak=index \
        --preview 'item={}; name=${item% ◀◀◀}; bpath=$(echo "$item" | command grep -oE "/[^ ]+$");
            if [[ -f ~/.config/tmuxinator/${name}.yml ]]; then
                [[ "$item" == *" ◀◀◀" ]] && echo "=== ACTIVE ===" && tmux list-windows -t "$name" -F "  #I: #W (#P panes)" 2>/dev/null && echo ""
                bat --color=always ~/.config/tmuxinator/${name}.yml 2>/dev/null || command cat ~/.config/tmuxinator/${name}.yml
            elif [[ -d "$item" ]]; then
                exa --color=always --long --all --header --icons --git "$item" 2>/dev/null || command ls -la "$item"
            elif [[ -f "$item" ]]; then
                bat --color=always "$item" 2>/dev/null || command cat "$item"
            elif [[ -n "$bpath" && -d "$bpath" ]]; then
                exa --color=always --long --all --header --icons --git "$bpath" 2>/dev/null || command ls -la "$bpath"
            elif [[ -n "$bpath" && -f "$bpath" ]]; then
                bat --color=always "$bpath" 2>/dev/null || command cat "$bpath"
            else
                echo "Preview not available"
            fi' \
        --preview-window 'right:50%:wrap' \
        --header ' C-f:files C-x:home C-b:github C-g:PRs C-i:Linear C-e:edit C-u:music C-k:kill | C-y:copy' \
        --prompt 'all> ' \
        --bind "$HOME_BIND" \
        --bind "$FILE_BIND" \
        --bind "$GITHUB_BIND" \
        --bind "$PR_BIND" \
        --bind "$LINEAR_BIND" \
        --bind "$EDIT_BIND" \
        --bind "$MUSIC_BIND" \
        --bind "$KILL_SESSION_BIND" \
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
    # Handle sessions (format: "name" or "name ◀◀◀")
    if [[ "$OUTPUT" =~ ^([a-zA-Z0-9_-]+)( ◀◀◀)?$ ]]; then
        session="${BASH_REMATCH[1]}"
        # Try switch first (works for any active session), fall back to tmuxinator
        if tmux switch-client -t "$session" 2>/dev/null; then
            exit 0
        elif [[ -f ~/.config/tmuxinator/${session}.yml ]]; then
            tmuxinator start "$session"
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