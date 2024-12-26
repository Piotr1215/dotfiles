import time
import os
import subprocess

active_window_title = subprocess.getoutput("xdotool getactivewindow getwindowname")

if 'Firefox' in active_window_title:
    try:
        layout = '/home/decoder/dev/dotfiles/scripts/__layouts.sh'
        keyboard.send_keys('<shift>+<alt>+d')  # Detaches tab into a new window
        time.sleep(0.25)  # Wait half a second for the action to complete

        subprocess.run([layout, "3"])
    except Exception as e:
        subprocess.run(['zenity', '--error', '--text', f"An error occurred: {e}"])


