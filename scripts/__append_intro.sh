#!/bin/bash

# Define your intro video and output directory
INTRO_VIDEO="/home/decoder/Downloads/Cloud Native Corner Intro.mp4"
OUTPUT_DIR="/home/decoder/Videos/"

# Check if the input video is provided
if [ -z "$1" ]; then
	echo "Usage: $0 <input_video>"
	exit 1
fi

INPUT_VIDEO="$1"
OUTPUT_VIDEO="$OUTPUT_DIR/$(basename "$INPUT_VIDEO" .mp4)_with_intro.mp4"

# Re-encode intro and input videos using NVENC to ensure compatibility
INTRO_TEMP=$(mktemp --suffix=.mp4)
INPUT_TEMP=$(mktemp --suffix=.mp4)

ffmpeg -i "$INTRO_VIDEO" -c:v h264_nvenc -preset fast -c:a aac -ar 44100 -ac 2 -y "$INTRO_TEMP"
ffmpeg -i "$INPUT_VIDEO" -c:v h264_nvenc -preset fast -c:a aac -ar 44100 -ac 2 -y "$INPUT_TEMP"

# Concatenate the videos
ffmpeg -f concat -safe 0 -i <(printf "file '$INTRO_TEMP'\nfile '$INPUT_TEMP'\n") -c copy "$OUTPUT_VIDEO"

# Clean up the temporary files
rm "$INTRO_TEMP" "$INPUT_TEMP"

echo "Output video created: $OUTPUT_VIDEO"
