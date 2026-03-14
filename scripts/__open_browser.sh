#!/usr/bin/env bash
set -eo pipefail

if [[ -f /tmp/timeoff_mode ]]; then
    flatpak run io.gitlab.librewolf-community -P "Home" "$@"
else
    google-chrome --profile-directory="Profile 1" "$@"
fi
