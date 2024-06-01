#!/bin/bash

# Define your intro video, outro video, and output directory
INTRO_VIDEO="/home/decoder/Videos/Piotr Intro with new Music.mp4"
OUTRO_VIDEO="/home/decoder/Videos/Piotr Outro.mp4"
OUTPUT_DIR="/home/decoder/Videos/"

# Check if the input video is provided
if [ -z "$1" ]; then
	echo "Usage: $0 <input_video>"
	exit 1
fi

INPUT_VIDEO="$1"
OUTPUT_VIDEO="$OUTPUT_DIR/$(basename "$INPUT_VIDEO" .mp4)_with_intro_outro.mp4"

# Re-encode intro, input, and outro videos using NVENC to ensure compatibility
INTRO_TEMP=$(mktemp --suffix=.mp4)
INPUT_TEMP=$(mktemp --suffix=.mp4)
OUTRO_TEMP=$(mktemp --suffix=.mp4)

ffmpeg -i "$INTRO_VIDEO" -c:v h264_nvenc -preset fast -c:a aac -ar 44100 -ac 2 -y "$INTRO_TEMP"
ffmpeg -i "$INPUT_VIDEO" -c:v h264_nvenc -preset fast -c:a aac -ar 44100 -ac 2 -y "$INPUT_TEMP"
ffmpeg -i "$OUTRO_VIDEO" -c:v h264_nvenc -preset fast -c:a aac -ar 44100 -ac 2 -y "$OUTRO_TEMP"

# Concatenate the videos
ffmpeg -f concat -safe 0 -i <(printf "file '%s'\nfile '%s'\nfile '%s'\n" "$INTRO_TEMP" "$INPUT_TEMP" "$OUTRO_TEMP") -c copy "$OUTPUT_VIDEO"

# Clean up the temporary files
rm "$INTRO_TEMP" "$INPUT_TEMP" "$OUTRO_TEMP"

echo "Output video created: $OUTPUT_VIDEO"
