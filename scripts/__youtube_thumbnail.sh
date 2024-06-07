#!/usr/bin/env bash

set -eo pipefail

# Add source and line number wher running in debug mode: __run_with_xtrace.sh __youtube_thumbnail.sh
# Set new line and tab for word splitting
IFS=$'\n\t'

if [ $(ls *.webp 2>/dev/null | wc -l) -eq 1 ]; then
	convert *.webp output.png
	convert output.png -resize 1280x720! output.png
	rm *.webp
fi
