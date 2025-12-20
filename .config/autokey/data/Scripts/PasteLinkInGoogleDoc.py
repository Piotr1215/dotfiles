import subprocess
import time

def is_google_docs():
    result = subprocess.run(['xdotool', 'getactivewindow', 'getwindowname'], stdout=subprocess.PIPE)
    window_name = result.stdout.decode('utf-8')
    return 'Google Docs' in window_name and ('Firefox' in window_name or 'LibreWolf' in window_name)

def is_clipboard_url():
    content = clipboard.get_clipboard()
    return content.startswith('http://') or content.startswith('https://')

if is_google_docs() and is_clipboard_url():
    keyboard.send_keys("<ctrl>+k")
    time.sleep(0.5)  # Wait for the dialog to open
    keyboard.send_keys("<shift>+<insert>")
    time.sleep(0.5)  # Wait for the link to be pasted
    keyboard.send_keys("<enter>")
else:
    keyboard.send_keys("<shift>+<insert>")
