#!/usr/bin/env bash

# Source generic error handling funcion
source __trap.sh

# The set -e option instructs bash to immediately exit if any command has a non-zero exit status
# The set -u referencing a previously undefined  variable - with the exceptions of $* and $@ - is an error
# The set -o pipefaile if any command in a pipeline fails, that return code will be used as the return code of the whole pipeline
# https://bit.ly/37nFgin
set -eo pipefail

# Add source and line number wher running in debug mode: __run_with_xtrace.sh __download_youtube.sh
# Set new line and tab for word splitting
IFS=$'\n\t'

link=$(xsel -ob)
if [[ "$link" != *"youtu"* ]]; then
	echo "This is not the right format, copy again"
	return 1 2>/dev/null
fi
# Download the video and save it as an MP4 file
yt-dlp -o "~/music/%(title)s.%(ext)s" --merge-output-format mp4 "$link" --no-playlist

video_title=$(yt-dlp --get-filename -o '%(title)s' --no-playlist "$link")
video_file=$(find ~/music -type f -iname "*${video_title}*" | head -n 1)

mp3_file="${video_file%.mp4}.mp3"

# Convert the video to MP3
if ffmpeg -i "$video_file" -vn -ar 44100 -ac 2 -b:a 192k "$mp3_file"; then
	# Remove the video file if the conversion is successful
	rm "$video_file"
	echo "Video converted to MP3 and video file removed."
else
	echo "Conversion failed."
	return 1 2>/dev/null
fi

# Rename the MP3 file according to the rules
new_mp3_file="$(echo "$mp3_file" | sed 's/[^a-zA-Z0-9.-]//g')"

mv "$mp3_file" "$HOME/music/$new_mp3_file"

echo "MP3 file renamed according to the rules."
