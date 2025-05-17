import os
import subprocess

# Alternative layout for alacirtty|bworser
layout = '/home/decoder/dev/dotfiles/scripts/__layouts.sh'

subprocess.run([layout, "2"])

# This focuses on alacritty once layout is active
subprocess.run(["xdotool", "key", "super+shift+l"])


