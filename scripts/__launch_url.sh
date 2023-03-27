#!/usr/bin/env bash

# This script launches a URL in the default browser
# without setting focus to the browser
# Source generic error handling funcion
source __trap.sh

# The set -e option instructs bash to immediately exit if any command has a non-zero exit status
# The set -u referencing a previously undefined  variable - with the exceptions of $* and $@ - is an error
# The set -o pipefaile if any command in a pipeline fails, that return code will be used as the return code of the whole pipeline
# https://bit.ly/37nFgin
set -eo pipefail

# Add source and line number wher running in debug mode: __run_with_xtrace.sh __launch_url.sh
# Set new line and tab for word splitting
IFS=$'\n\t'

# Save the active window ID
active_window_id=$(xdotool getactivewindow)

# Open the URL
xdg-open "$1" >/dev/null 2>&1 &

# Wait for the browser to open the URL
sleep 1

# Return focus to the terminal
xdotool windowactivate "$active_window_id"
