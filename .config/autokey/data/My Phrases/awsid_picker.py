import subprocess
# backspace:false in the .json -> the picker erases the trigger itself.
# Arg "7" = len(";;awsid"): backspace that many chars before typing the value.
subprocess.Popen(["/home/decoder/dev/dotfiles/scripts/__value_picker.sh", "awsid", "7"])
