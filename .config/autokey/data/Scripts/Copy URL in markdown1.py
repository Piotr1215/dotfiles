import subprocess
active_window_title = subprocess.getoutput("xdotool getactivewindow getwindowname")

if 'Firefox' in active_window_title or 'Chrome' in active_window_title or 'Brave' in active_window_title or 'LibreWolf' in active_window_title:
    clipboard.fill_clipboard("")  
    keyboard.send_keys('yy')
    time.sleep(0.5)
    description = clipboard.get_selection()
    url = clipboard.get_clipboard()
    combined = f"[{description}]({url})"

    clipboard.fill_clipboard(combined)
