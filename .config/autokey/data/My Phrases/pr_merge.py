import subprocess
# backspace:false in the .json -> the script erases the trigger itself.
# Arg "7" = len(";;merge"): backspace that many chars before pasting.
subprocess.Popen(["/home/decoder/dev/dotfiles/scripts/__pr_merge_pick.sh", "7"])
