#!/bin/bash

# Path to the Haruna playlist file
# PROJECT: playlist
playlist_file="$HOME/haruna_playlist.m3u"

# Launch Haruna with the playlist
mpv "$playlist_file"
