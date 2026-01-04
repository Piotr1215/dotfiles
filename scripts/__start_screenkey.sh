#!/usr/bin/env bash

set -eo pipefail

# Add source and line number wher running in debug mode: __run_with_xtrace.sh __start_screenkey.sh
# Set new line and tab for word splitting
IFS=$'\n\t'

# Start screenkey for presentations/recordings
screenkey \
    --position bottom \
    --font-size small \
    --font "JetBrainsMono Nerd Font" \
    --font-color "#f2f4f8" \
    --bg-color "#161616" \
    --timeout 2 \
    --compr-cnt 2 \
    --opacity 0.8 \
    --no-systray &
