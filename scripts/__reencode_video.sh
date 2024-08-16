#!/bin/bash

# Define your output directory
OUTPUT_DIR="/home/decoder/Videos/"

# Check if the input video is provided
if [ -z "$1" ]; then
	echo "Usage: $0 <input_video>"
	exit 1
fi

INPUT_VIDEO="$1"
OUTPUT_VIDEO="$OUTPUT_DIR/$(basename "$INPUT_VIDEO" .mp4)_reencoded.mp4"

# Re-encode the input video using NVENC with a higher bitrate to ensure quality
ffmpeg -i "$INPUT_VIDEO" -c:v h264_nvenc -preset slow -b:v 8M -c:a aac -ar 44100 -ac 2 -y "$OUTPUT_VIDEO"

echo "Re-encoded video created: $OUTPUT_VIDEO"
