#!/usr/bin/env bash

set -eo pipefail
IFS=$'\n\t'

# Check for -mp3 flag
convert_to_mp3=false
if [[ "$1" == "-mp3" ]]; then
	convert_to_mp3=true
fi

echo "Step 1: Checking the link format."

link=$(xsel -ob)
if [[ "$link" != *"youtu"* ]]; then
	echo "This is not the right format, copy again."
	exit 1
fi

# Determine the output directory based on the flag
output_dir="$HOME/Videos"
if [ "$convert_to_mp3" = true ]; then
	output_dir="$HOME/music"
fi

echo "Step 2: Downloading the video to $output_dir."

yt-dlp -o "$output_dir/%(title)s.%(ext)s" --merge-output-format webm "$link" --no-playlist

video_title=$(yt-dlp --get-filename -o '%(title)s' --no-playlist "$link")
video_file=$(find "$output_dir" -type f -iname "*${video_title}*" | head -n 1)

# If -mp3 flag is not passed, exit after downloading
if [ "$convert_to_mp3" = false ]; then
	echo "Video downloaded. Exiting."
	exit 0
fi

echo "Step 3: Preparing for MP3 conversion."

mp3_file="${video_file%.webm}.mp3"

echo "Step 4: Converting to MP3."

if ffmpeg -i "$video_file" -vn -ar 44100 -ac 2 -b:a 192k "$mp3_file"; then
	echo "Step 5: Removing the original video file."
	rm "$video_file"
	echo "Video converted to MP3 and original video file removed."
else
	echo "Conversion failed."
	exit 1
fi

echo "Step 6: Renaming the MP3 file."

# Extract just the filename part
filename=$(basename "$mp3_file")
new_mp3_file="$(echo "$filename" | sed 's/[^a-zA-Z0-9.-]//g')"
mv "$mp3_file" "$HOME/music/$new_mp3_file"

echo "MP3 file renamed according to the rules."
