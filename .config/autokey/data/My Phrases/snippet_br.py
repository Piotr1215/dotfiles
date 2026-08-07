import subprocess
# backspace:false in the .json -> the script erases the trigger itself.
# Arg "4" = len(";;br"): backspace that many chars before pasting.
subprocess.Popen(["/home/decoder/dev/dotfiles/scripts/__snippet_picker.sh", "4", "open-the-link"])
