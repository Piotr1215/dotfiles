#!/usr/bin/env bash

lock_file="/tmp/check_vids.lock"

# Exit if another instance is already running
if [[ -e $lock_file ]]; then
	exit 0
fi

# Create a lock file to indicate this instance is running
touch $lock_file

# Function to check if yt-dlp is running
check_ytdlp() {
	ps -ef | grep -v grep | grep yt-dlp >/dev/null
	return $?
}

# Wait for all yt-dlp processes to complete
while check_ytdlp; do
	sleep 10 # wait for 10 seconds before checking again
done

# Display a notification using Zenity
zenity --notification --text="All videos have been downloaded."

# Remove the lock file to allow future instances to run
rm $lock_file
