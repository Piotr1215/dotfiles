import subprocess
# backspace:false in the .json -> the picker erases the trigger itself.
# Arg "7" = len(";;skill"): backspace that many chars before typing the value.
subprocess.Popen(["/home/decoder/dev/dotfiles/scripts/__value_picker.sh", "skills", "7"])
