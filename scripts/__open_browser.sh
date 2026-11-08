#!/usr/bin/env bash
set -eo pipefail

# Open the browser for the current ufp mode: Chrome's loft.sh profile in work
# mode, LibreWolf's Home profile in home mode. BROWSER points here, so the mode
# is read when a URL opens, not when a shell starts.
mode_file="${TIMEOFF_MODE_FILE:-/tmp/timeoff_mode}"

if [[ -f "$mode_file" ]]; then
    flatpak run io.gitlab.librewolf-community -P "Home" "$@"
else
    google-chrome --profile-directory="Profile 1" "$@"
fi
