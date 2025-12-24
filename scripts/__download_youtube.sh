#!/usr/bin/env bash
set -eo pipefail
IFS=$'\n\t'

check_and_update_ytdlp() {
	if ! command -v pipx &>/dev/null; then
		python3 -m pip install --user pipx
		python3 -m pipx ensurepath
		source ~/.zshrc
	fi
	if ! pipx list | grep -q yt-dlp; then
		pipx install yt-dlp
	else
		pipx upgrade yt-dlp
	fi
	yt-dlp --version
}

download_video() {
	local link="$1"
	local output_dir="$2"
	local convert_to_mp3="$3"

	if [[ ! "$link" =~ youtu ]]; then
		echo "Invalid URL: $link"
		return 1
	fi

	if [ "$convert_to_mp3" = true ]; then
		# Direct audio download with sanitized filename
		if ! yt-dlp -x --audio-format mp3 --audio-quality 192K \
			--restrict-filenames \
			-o "$output_dir/%(title)s.%(ext)s" \
			--no-playlist "$link"; then
			echo "Download failed for: $link"
			return 1
		fi
	else
		# Video download
		if ! yt-dlp --restrict-filenames \
			-o "$output_dir/%(title)s.%(ext)s" \
			--merge-output-format mp4 \
			--no-playlist "$link"; then
			if ! yt-dlp --restrict-filenames \
				-o "$output_dir/%(title)s.%(ext)s" \
				-f best --no-playlist "$link"; then
				echo "Download failed for: $link"
				return 1
			fi
		fi
	fi
}

export -f download_video

process_urls() {
	local output_dir="$HOME/Videos"
	[ "$convert_to_mp3" = true ] && output_dir="$HOME/music"

	if [ ${#urls[@]} -gt 1 ]; then
		printf '%s\n' "${urls[@]}" | xargs -P 4 -I {} bash -c "download_video '{}' '$output_dir' '$convert_to_mp3'"
	else
		download_video "${urls[0]}" "$output_dir" "$convert_to_mp3"
	fi
}

convert_to_mp3=false
[[ "$1" == "-mp3" ]] && {
	convert_to_mp3=true
	shift
}
export convert_to_mp3

check_and_update_ytdlp

if [ -f "$1" ]; then
	mapfile -t urls <"$1"
elif [ $# -gt 0 ]; then
	urls=("$@")
else
	urls=($(xsel -ob))
fi

process_urls
