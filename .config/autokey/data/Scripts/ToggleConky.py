import subprocess
from os.path import expanduser

def is_conky_running():
    try:
        subprocess.check_output(['pgrep', 'conky'])
        return True
    except subprocess.CalledProcessError:
        return False

if is_conky_running():
    subprocess.call(['killall', 'conky'])
else:
    config_path = expanduser('~/.config/conky/Mirach/Mirach.conf')
    subprocess.call(['conky', '-c', config_path])
