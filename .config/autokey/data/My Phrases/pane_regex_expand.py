import subprocess
# backspace:false in the .json -> the script erases the trigger itself.
# Arg "3" = len(";;^"): backspace that many chars before pasting.
subprocess.Popen(["/home/decoder/dev/dotfiles/scripts/__pane_regex_expand.py", "3"])
