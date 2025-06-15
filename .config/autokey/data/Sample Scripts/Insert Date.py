import subprocess

output = system.exec_command("date")
output = output.strip()

clipboard.fill_text(output)
keyboard.send_keys("<ctrl>+v")