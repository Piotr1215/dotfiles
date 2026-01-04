#!/usr/bin/env bash
# Copy path to clipboard

set -eo pipefail

# Extract path from fzf selection
path=$(~/dev/dotfiles/scripts/__extract_path_from_fzf.sh "$1")

# Copy to clipboard (sleep lets xclip fork before fzf exits)
printf '%s' "$path" | xclip -selection clipboard
sleep 0.1
