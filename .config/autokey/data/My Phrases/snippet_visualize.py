import subprocess
# backspace:false in the .json -> the script erases the trigger itself.
# Arg "11" = len(";;visualize"): backspace that many chars before pasting.
subprocess.Popen(["/home/decoder/dev/dotfiles/scripts/__snippet_picker.sh", "11", "visualize"])
