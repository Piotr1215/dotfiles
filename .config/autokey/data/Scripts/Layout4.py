import os
import subprocess

layout = '/home/decoder/dev/dotfiles/scripts/__layouts.sh'

# Slack -> Alacritty
subprocess.run([layout, "9"])

