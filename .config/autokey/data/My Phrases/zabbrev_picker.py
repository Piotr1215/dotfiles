import subprocess
# backspace:false in the .json -> the picker erases the trigger itself.
# Arg "8" = len(";;abbrev"): backspace that many chars before typing the value.
subprocess.Popen(["/home/decoder/dev/dotfiles/scripts/__value_picker.sh", "zabbrev", "8"])
