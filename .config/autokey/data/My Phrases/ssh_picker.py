import subprocess
# backspace:false in the .json -> the picker erases the trigger itself.
# Arg "5" = len(";;ssh"): backspace that many chars before typing the value.
subprocess.Popen(["/home/decoder/dev/dotfiles/scripts/__value_picker.sh", "ssh", "5"])
