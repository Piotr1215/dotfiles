#!/usr/bin/env bash

set -eo pipefail

# Add source and line number wher running in debug mode: __run_with_xtrace.sh __start_screenkey.sh
# Set new line and tab for word splitting
IFS=$'\n\t'

# Start screenkey with large font size and fixed position at the bottom of the screen
screenkey &
