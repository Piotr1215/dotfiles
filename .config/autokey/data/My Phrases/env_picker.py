import subprocess
# backspace:false in the .json -> the picker erases the trigger itself.
# Arg "5" = len(";;env"): backspace that many chars before typing the value.
subprocess.Popen(["/home/decoder/dev/dotfiles/scripts/__value_picker.sh", "env", "5"])
