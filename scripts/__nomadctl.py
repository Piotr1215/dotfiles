#!/usr/bin/env python3
"""Start, stop, and inspect the local NOMAD stack."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from urllib.error import URLError
from urllib.request import Request, ProxyHandler, build_opener

EXPECTED_UUID = 'd74106d0-1b12-4d65-873d-d69ed3a729e6'
COMPOSE = ['docker', 'compose', '-f', '/opt/project-nomad/compose.yml']
LABELS = ['--filter', 'label=io.project-nomad.managed=true', '--filter', 'label=com.docker.compose.project=project-nomad-managed']
MANAGED_ALL = ['docker', 'ps', '-aq', *LABELS]
MANAGED_STOPPED = ['docker', 'ps', '-aq', *LABELS, '--filter', 'status=exited', '--filter', 'status=created', '--format', '{{.ID}} {{.Names}}']
BASE_STATUS = ['docker', 'ps', '-a', '--filter', 'label=com.docker.compose.project=project-nomad', '--format', '{{.Names}}\t{{.Status}}']
MANAGED_STATUS = ['docker', 'ps', '-a', *LABELS, '--format', '{{.Names}}\t{{.Status}}']
UNIT = 'nomad-downloads.service'
URL = 'http://localhost:1215/home'
REMOTE_UNIT = 'nomad-remote-ollama.service'
REMOTE_PROFILE = Path('/home/decoder/.local/share/nomad-setup/remote-ollama.json')


def remote_profile():
    if not REMOTE_PROFILE.exists():
        return None
    return json.loads(REMOTE_PROFILE.read_text())


def request_json(url, data=None):
    payload = json.dumps(data).encode() if data is not None else None
    request = Request(url, data=payload, headers={'Content-Type': 'application/json'})
    with build_opener(ProxyHandler({})).open(request, timeout=10) as response:
        return json.load(response)


def unload_remote(profile):
    try:
        selected = request_json('http://127.0.0.1:1215/api/system/settings?key=chat.lastModel').get('value') or profile['model']
        loaded = request_json(profile['url'] + '/api/ps').get('models', [])
        if any(model.get('name') == selected for model in loaded):
            request_json(profile['url'] + '/api/generate', {'model': selected, 'prompt': '', 'keep_alive': 0, 'stream': False})
        return True
    except (OSError, URLError, ValueError, KeyError, TypeError) as exc:
        print(f'Remote model unload could not be confirmed: {exc}', file=sys.stderr)
        return False


def run(args):
    env = os.environ.copy()
    runtime = f'/run/user/{os.getuid()}'
    env.setdefault('XDG_RUNTIME_DIR', runtime)
    env.setdefault('DBUS_SESSION_BUS_ADDRESS', f'unix:path={runtime}/bus')
    try:
        return subprocess.run(args, text=True, capture_output=True, env=env, check=False)
    except OSError as exc:
        print(f"{args[0]}: {exc}", file=sys.stderr)
        return None


def checked(args):
    result = run(args)
    if result is None:
        return None
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip() or f'exit {result.returncode}'
        print(f"{' '.join(args)}: {detail}", file=sys.stderr)
        return None
    return result


def containers(query, action, exclude_names=()):
    result = checked(query)
    if result is None:
        return False
    rows = [line.split() for line in result.stdout.splitlines() if line.strip()]
    ids = [row[0] for row in rows if len(row) == 1 or row[1] not in exclude_names]
    return not ids or checked(['docker', action, *ids]) is not None


def open_page():
    browser = shutil.which('google-chrome-stable') or shutil.which('google-chrome')
    if not browser or not (os.environ.get('DISPLAY') or os.environ.get('WAYLAND_DISPLAY')):
        print('Browser not opened: no Chrome desktop session is available.', file=sys.stderr)
        return
    try:
        subprocess.Popen([browser, '--new-tab', URL], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError as exc:
        print(f'Browser not opened: {exc}', file=sys.stderr)


def rescan_library():
    # Downloads finished while NOMAD was off are moved into zim/ but never registered.
    try:
        request_json('http://127.0.0.1:1215/api/zim/rescan-library', {})
    except (OSError, URLError, ValueError) as exc:
        print(f'Library rescan failed: {exc}', file=sys.stderr)


def on(open_browser=True):
    result = checked(['findmnt', '-n', '-o', 'UUID', '--target', '/mnt/nvme-backup'])
    if result is None:
        return 1
    if result.stdout.strip() != EXPECTED_UUID:
        print('NOMAD drive UUID does not match; refusing to start.', file=sys.stderr)
        return 1
    if checked(COMPOSE + ['up', '-d', '--pull', 'never', '--wait', '--wait-timeout', '180']) is None:
        return 1
    remote = remote_profile()
    if remote and checked(['systemctl', '--user', 'enable', '--now', REMOTE_UNIT]) is None:
        return 1
    if not containers(MANAGED_STOPPED, 'start', exclude_names=('nomad_ollama',) if remote else ()):
        return 1
    if remote and remote.get('fallback_unit') and checked(['systemctl', '--user', 'enable', '--now', remote['fallback_unit']]) is None:
        return 1
    if checked(['systemctl', '--user', 'enable', '--now', UNIT]) is None:
        return 1
    rescan_library()
    print(f'NOMAD ready: {URL}')
    if open_browser:
        open_page()
    return 0


def off():
    remote = remote_profile()
    success = unload_remote(remote) if remote else True
    if checked(['systemctl', '--user', 'disable', '--now', UNIT]) is None:
        success = False
    if remote and remote.get('fallback_unit') and checked(['systemctl', '--user', 'disable', '--now', remote['fallback_unit']]) is None:
        success = False
    if not containers(MANAGED_ALL, 'stop'):
        success = False
    if checked(COMPOSE + ['stop']) is None:
        success = False
    if remote and checked(['systemctl', '--user', 'disable', '--now', REMOTE_UNIT]) is None:
        success = False
    return 0 if success else 1


def status():
    success = True
    for label, command in [('Core', BASE_STATUS), ('Apps', MANAGED_STATUS)]:
        result = checked(command)
        if result is None:
            success = False
        else:
            print(f'{label}:')
            print(result.stdout.strip() or '  none')
    for verb in ('is-active', 'is-enabled'):
        result = run(['systemctl', '--user', verb, UNIT])
        if result is None:
            success = False
        else:
            state = result.stdout.strip()
            print(f'Downloader {verb[3:]}: {state or "unknown"}')
            if result.returncode and state not in ('inactive', 'failed', 'disabled', 'static', 'masked', 'indirect', 'generated', 'transient'):
                print(result.stderr.strip() or f'systemctl {verb}: exit {result.returncode}', file=sys.stderr)
                success = False
    return 0 if success else 1


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('on', 'off', 'stop', 'status'))
    parser.add_argument('--no-browser', action='store_true', help='start without opening Chrome')
    args = parser.parse_args(argv)
    if args.command == 'on':
        return on(open_browser=not args.no_browser)
    return {'off': off, 'stop': off, 'status': status}[args.command]()


if __name__ == '__main__':
    sys.exit(main())
