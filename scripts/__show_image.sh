#!/bin/bash

# Determine the temporary directory
case "$(uname -a)" in
*Darwin*) UEBERZUG_TMP_DIR="$TMPDIR" ;;
*) UEBERZUG_TMP_DIR="/tmp" ;;
esac

# Cleanup function
cleanup() {
	ueberzugpp cmd -s "$SOCKET" -a exit
}

# Set trap for cleanup
trap cleanup HUP INT QUIT TERM EXIT

# Generate a unique PID file
UB_PID_FILE="$UEBERZUG_TMP_DIR/.$(uuidgen)"

# Start Überzugpp layer
ueberzugpp layer --no-stdin --silent --use-escape-codes --pid-file "$UB_PID_FILE"

# Get the PID and set up the socket
UB_PID=$(cat "$UB_PID_FILE")
export SOCKET="$UEBERZUG_TMP_DIR"/ueberzugpp-"$UB_PID".socket

# Function to display an image
display_image() {
	local path="$1"
	local x="$2"
	local y="$3"
	local max_width="$4"
	local max_height="$5"

	ueberzugpp cmd -s "$SOCKET" -i preview -a add -x "$x" -y "$y" --max-width "$max_width" --max-height "$max_height" -f "$path"
}

# Check if image path is provided
if [ -z "$1" ]; then
	echo "Usage: $0 <image_path>"
	exit 1
fi

IMAGE_PATH="$1"

# Pane dimensions for the target pane (90x46)
PANE_WIDTH=90
PANE_HEIGHT=46

# Calculate center position within the pane
X=0
Y=0
MAX_WIDTH=$PANE_WIDTH
MAX_HEIGHT=$PANE_HEIGHT

# Display the image
display_image "$IMAGE_PATH" "$X" "$Y" "$MAX_WIDTH" "$MAX_HEIGHT"

# Wait for user input
read -p ""

# Cleanup
cleanup
