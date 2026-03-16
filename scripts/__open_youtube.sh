#!/usr/bin/env bash

# Launch LibreWolf with YouTube (personal browser)
# NOTE: -P "Home" breaks when profile already running (profile lock, URL silently dropped)
flatpak run io.gitlab.librewolf-community "https://youtube.com" &
sleep 2
wmctrl -a librewolf
