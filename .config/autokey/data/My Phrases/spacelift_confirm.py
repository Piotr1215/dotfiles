import subprocess
# backspace:false in the .json -> the script erases the trigger itself.
# Arg "11" = len(";;spacelift"): backspace that many chars before pasting.
subprocess.Popen(["/home/decoder/dev/dotfiles/scripts/__spacelift_confirm_pick.sh", "11"])
