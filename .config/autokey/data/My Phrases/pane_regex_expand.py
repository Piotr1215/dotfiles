import subprocess

# backspace:false in the .json -> the script erases the trigger itself.
# Arg "3" = len(";;^"): backspace that many chars before pasting.
try:
    script = subprocess.check_output(
        ["tmux", "show-option", "-gqv", "@pane-regex-script"], text=True
    ).strip()
except (OSError, subprocess.CalledProcessError):
    script = ""

if script:
    subprocess.Popen([script, "3"])
