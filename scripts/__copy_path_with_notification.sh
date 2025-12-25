#!/usr/bin/env bash
# Copy path to clipboard and show notification

set -eo pipefail

# Configuration
NOTIFICATION_TIMEOUT="${COPY_NOTIFICATION_TIMEOUT:-1000}"

# Extract path from fzf selection
path=$(~/dev/dotfiles/scripts/__extract_path_from_fzf.sh "$1")

# Copy to clipboard without newline
~/dev/dotfiles/scripts/__clipboard_copy.sh "$path"

# Show notification with the actual path
notify-send -t "$NOTIFICATION_TIMEOUT" 'Path Copied' "$path"
