import os
import subprocess

# Claude in Firefox + Alacritty layout
layout = '/home/decoder/dev/dotfiles/scripts/__layouts.sh'

subprocess.run([layout, "10"])
