#!/usr/bin/env python3
"""Install this checkout's native-messaging manifest for the Tab sweep extension.

The ID in allowed_origins comes from the `key` in
.config/chrome-tab-sweep/manifest.json (first 16 bytes of SHA-256 over the
DER key, each nibble mapped to a-p), so the two cannot drift.
"""
import base64
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
key = json.loads((root / '.config/chrome-tab-sweep/manifest.json').read_text())['key']
digest = hashlib.sha256(base64.b64decode(key)).digest()[:16]
extension_id = ''.join(chr(ord('a') + (byte >> shift & 0x0f)) for byte in digest for shift in (4, 0))
manifest = {
    'name': 'org.piotr.tab_sweep',
    'description': 'Find merged-PR and duplicate tabs for the Tab sweep extension and report closes to Gordon',
    'path': str(root / 'scripts/__chrome_tab_sweep.py'),
    'type': 'stdio',
    'allowed_origins': [f'chrome-extension://{extension_id}/'],
}
directory = Path.home() / '.config/google-chrome/NativeMessagingHosts'
directory.mkdir(mode=0o700, parents=True, exist_ok=True)
file = directory / (manifest['name'] + '.json')
file.write_text(json.dumps(manifest, indent=2) + '\n')
file.chmod(0o600)
print(f'{file} -> {extension_id}')
