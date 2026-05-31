import subprocess
# backspace:false in the .json -> __bang_pick.sh erases the ";;?" trigger itself
# (after rofi closes), then types the chosen trigger so AutoKey re-fires it.
subprocess.Popen(["/home/decoder/dev/dotfiles/scripts/__bang_pick.sh"])
