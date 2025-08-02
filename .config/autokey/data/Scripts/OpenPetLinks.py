import subprocess
# Use tmux to run the script in a popup, just like the tmux binding does
subprocess.run(["tmux", "display-popup", "-E", "/home/decoder/dev/dotfiles/scripts/__link_pane_runner.sh"])
