#!/usr/bin/env python3
"""Open or select a handoff URL through the signed-in Chrome bridge."""
import asyncio
import json
import os
from pathlib import Path
import sys
from urllib.parse import urlsplit

sys.path.insert(0, str(Path.home() / '.codex/scripts/agent_browser'))
from client import RequestClient
from paths import default_socket_path


async def open_tab(url, focus=False):
    parsed = urlsplit(url)
    if (parsed.scheme != 'https' or not parsed.hostname or parsed.username is not None
            or parsed.password is not None or parsed.port is not None
            or any(ord(char) <= 32 or ord(char) == 127 for char in url) or '\\' in url):
        raise ValueError('handoff URL must be an unambiguous HTTPS URL')
    client = RequestClient(os.environ.get('AGENT_BROWSER_NATIVE_SOCKET') or default_socket_path())
    await client.connect()
    try:
        result = await client.request({'action': 'handoff', 'agent': 'handoffs', 'url': url, 'focus': focus})
    finally:
        await client.close()
    if result.get('event') not in ('created', 'existing'):
        raise RuntimeError('Chrome bridge could not open handoff tab')
    return result


def main():
    focus = len(sys.argv) == 3 and sys.argv[1] == '--focus'
    if len(sys.argv) != (3 if focus else 2):
        print('usage: __handoff_tab.py [--focus] URL', file=sys.stderr)
        return 2
    try:
        result = asyncio.run(open_tab(sys.argv[-1], focus))
        print(json.dumps(result))
        return 0
    except (OSError, RuntimeError, ValueError, asyncio.TimeoutError) as error:
        print(f'Chrome handoff: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
