import os
import subprocess
import time

# Alternative layout for alacirtty|bworser
layout = '/home/decoder/dev/dotfiles/scripts/__layouts.sh'

subprocess.run([layout, "2"])

# Add small delay to prevent key event conflicts
time.sleep(0.2)

# This focuses on alacritty once layout is active
subprocess.run(["xdotool", "key", "super+shift+l"])


