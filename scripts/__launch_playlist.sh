#!/bin/bash

# Path to the Haruna playlist file
# PROJECT: playlist

if [[ -z $1 ]]; then
	playlist_file="$HOME/haruna_playlist.m3u"
else
	playlist_file="$HOME/$1.m3u"
fi

# Launch playlist, this will pick best available resolution for the vid
mpv "$playlist_file"
