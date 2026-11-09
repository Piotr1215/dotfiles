#!/usr/bin/env python3
"""Install this checkout's Chrome native-messaging manifest for the user."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[2]
host = root / 'scripts/__chrome_agent_tmux.py'
manifest = {
    'name': 'org.piotr.agent_tab_tmux',
    'description': 'Switch tmux to the owner of an activated Chrome tab',
    'path': str(host),
    'type': 'stdio',
    'allowed_origins': ['chrome-extension://onlalgjmoaahoijjkpdgijadcnihipao/'],
}
directory = Path.home() / '.config/google-chrome/NativeMessagingHosts'
directory.mkdir(mode=0o700, parents=True, exist_ok=True)
file = directory / (manifest['name'] + '.json')
file.write_text(json.dumps(manifest, indent=2) + '\n')
file.chmod(0o600)
