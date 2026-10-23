import os
import subprocess

# backspace:false in the .json -> the script erases the trigger itself.
# Arg "3" = len(";;^"): backspace that many chars before pasting.
#
# AutoKey runs outside tmux but keeps the TMUX and TMUX_PANE of the shell that
# last restarted it, often an agent's pane. tmux answers the plugin's "pane on
# screen" lookup from the caller's TMUX_PANE, so ;;^ searched that agent pane.
# Name the focused client's pane outright and drop both variables.
LIB = "/home/decoder/dev/dotfiles/scripts/__lib_pane_deliver.sh"
env = {k: v for k, v in os.environ.items() if k not in ("TMUX", "TMUX_PANE")}


def output(command):
    try:
        return subprocess.check_output(command, text=True, env=env).strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


script = output(["tmux", "show-option", "-gqv", "@pane-regex-script"])
pane = output(["bash", "-c", 'source "$1" && focused_client_pane', "_", LIB])

if script:
    command = [script, "3"]
    if pane:
        command += ["--pane", pane]
    subprocess.Popen(command, env=env)
