import importlib.util
import json
import struct
import os
import pty
import subprocess
import time
import uuid
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('host', ROOT / 'scripts/__chrome_agent_tmux.py')
host = importlib.util.module_from_spec(spec)
spec.loader.exec_module(host)


@pytest.fixture
def server(monkeypatch, request):
    socket = 'agent-tab-test-' + uuid.uuid4().hex
    monkeypatch.setenv('AGENT_TMUX_TEST_SOCKET', socket)
    cmd = ['tmux', '-L', socket, '-f', '/dev/null']
    client = None
    master = None

    def cleanup():
        subprocess.run(cmd + ['kill-server'], capture_output=True)
        if client is not None:
            client.wait(timeout=5)
        if master is not None:
            os.close(master)

    request.addfinalizer(cleanup)
    subprocess.run(cmd + ['new-session', '-d', '-s', 'start'], check=True)
    subprocess.run(cmd + ['new-session', '-d', '-s', 'agent'], check=True)
    subprocess.run(cmd + ['set-option', '-p', '-t', '=agent:.0', '@agent_name', 'agent'], check=True)
    master, slave = pty.openpty()
    try:
        client = subprocess.Popen(cmd + ['attach-session', '-t', '=start'], stdin=slave, stdout=slave, stderr=slave, env={**os.environ, 'TERM': 'xterm'})
    finally:
        os.close(slave)
    for _ in range(100):
        if subprocess.run(cmd + ['list-clients'], capture_output=True).stdout:
            break
        time.sleep(.02)
    else:
        pytest.fail('tmux client did not attach')
    return cmd


def selected(cmd):
    return subprocess.check_output(cmd + ['list-clients', '-F', '#{session_name}'], text=True).strip()


def test_switches_owned_session(server):
    assert host.handle({'owner': 'agent'}) == {'switched': True, 'rule': 'title'}
    assert selected(server) == 'agent'


@pytest.mark.parametrize('owner', ['', 'missing', 'start', 'agent\nstart', None, 12])
def test_skips_unknown_or_invalid_owner(server, owner):
    assert host.handle({'owner': owner}) == {'switched': False}
    assert selected(server) == 'start'


def test_ambiguous_clients_do_not_switch(server):
    master, slave = pty.openpty()
    client = subprocess.Popen(server + ['attach-session', '-t', '=start'], stdin=slave, stdout=slave, stderr=slave, env={**os.environ, 'TERM': 'xterm'})
    os.close(slave)
    try:
        for _ in range(100):
            if len(subprocess.check_output(server + ['list-clients'], text=True).splitlines()) == 2:
                break
            time.sleep(.02)
        assert host.handle({'owner': 'agent'}) == {'switched': False}
        assert selected(server).splitlines() == ['start', 'start']
    finally:
        client.terminate()
        client.wait(timeout=5)
        os.close(master)


def test_native_message_protocol_switches_owned_session(server):
    payload = json.dumps({'owner': 'agent'}).encode()
    result = subprocess.run(
        [str(ROOT / 'scripts/__chrome_agent_tmux.py')],
        input=struct.pack('=I', len(payload)) + payload,
        capture_output=True, check=True,
    )
    length = struct.unpack('=I', result.stdout[:4])[0]
    assert json.loads(result.stdout[4:4 + length]) == {'switched': True, 'rule': 'title'}
    assert selected(server) == 'agent'


def test_host_installer_targets_checkout(tmp_path):
    subprocess.run(
        ['python3', str(ROOT / '.config/chrome-agent-tmux/install-host.py')],
        env={**os.environ, 'HOME': str(tmp_path)}, check=True,
    )
    manifest = tmp_path / '.config/google-chrome/NativeMessagingHosts/org.piotr.agent_tab_tmux.json'
    data = json.loads(manifest.read_text())
    assert data['path'] == str(ROOT / 'scripts/__chrome_agent_tmux.py')
    assert data['allowed_origins'] == ['chrome-extension://onlalgjmoaahoijjkpdgijadcnihipao/']
    assert manifest.stat().st_mode & 0o777 == 0o600


@pytest.fixture
def tabs(tmp_path, monkeypatch):
    monkeypatch.setenv('XDG_STATE_HOME', str(tmp_path))
    path = tmp_path / 'agent-tabs/tabs.jsonl'
    path.parent.mkdir()

    def write(*rows):
        path.write_text(''.join(json.dumps(r) + '\n' for r in rows))
    return write


def row(tab, pane, ts=1):
    return {'tab_id': tab, 'pane': pane, 'session': 'x', 'agent': '', 'ts': ts}


def pane_of(cmd, target):
    return subprocess.check_output(cmd + ['display', '-p', '-t', target, '#{pane_id}'], text=True).strip()


def current(cmd):
    return subprocess.check_output(
        cmd + ['list-clients', '-F', '#{session_name} #{window_index} #{pane_id}'], text=True).strip()


def test_tab_id_hit_in_shared_session(server, tabs):
    # Two windows in one session, the way Gordon and Kendra share `task`.
    subprocess.run(server + ['new-window', '-t', '=agent:'], check=True)
    subprocess.run(server + ['new-window', '-t', '=agent:'], check=True)
    subprocess.run(server + ['split-window', '-t', '=agent:1'], check=True)
    target = pane_of(server, '=agent:1.0')
    subprocess.run(server + ['select-window', '-t', '=agent:2'], check=True)
    tabs(row(7, target))
    assert host.handle({'tabId': 7, 'groupTabIds': [], 'owner': 'Claude'}) == {'switched': True, 'rule': 'tab_id'}
    sess, win, pane = current(server).split()
    assert (sess, win, pane) == ('agent', '1', target)


def test_group_sibling_hit(server, tabs):
    target = pane_of(server, '=agent:.0')
    tabs(row(8, target))
    assert host.handle({'tabId': 9, 'groupTabIds': [9, 8], 'owner': 'Claude'}) == {'switched': True, 'rule': 'group_sibling'}
    assert current(server).split()[0] == 'agent'


def test_stale_pane_ignored(server, tabs):
    tabs(row(7, '%9999'))
    assert host.handle({'tabId': 7, 'groupTabIds': [7], 'owner': 'Claude'}) == {'switched': False}
    assert current(server).split()[0] == 'start'


def test_newest_line_wins(server, tabs):
    old = pane_of(server, '=start:.0')
    new = pane_of(server, '=agent:.0')
    tabs(row(7, new, 5), row(7, old, 2))
    assert host.handle({'tabId': 7, 'groupTabIds': []})['rule'] == 'tab_id'
    assert current(server).split()[0] == 'agent'
    subprocess.run(server + ['switch-client', '-t', '=start'], check=True)
    tabs(row(7, old, 5), row(7, new, 9))
    host.handle({'tabId': 7, 'groupTabIds': []})
    assert current(server).split()[0] == 'agent'


def test_newest_sibling_wins(server, tabs):
    tabs(row(1, pane_of(server, '=start:.0'), 2), row(2, pane_of(server, '=agent:.0'), 8))
    assert host.handle({'tabId': 3, 'groupTabIds': [1, 2]})['rule'] == 'group_sibling'
    assert current(server).split()[0] == 'agent'


def test_title_fallback(server, tabs):
    tabs(row(7, '%9999'))
    assert host.handle({'tabId': 5, 'groupTabIds': [5], 'owner': 'agent'}) == {'switched': True, 'rule': 'title'}


def test_no_match(server, tabs):
    assert host.handle({'tabId': 5, 'groupTabIds': [5], 'owner': 'Claude'}) == {'switched': False}
    assert host.handle({'tabId': 5, 'groupTabIds': [], 'owner': ''}) == {'switched': False}
    assert current(server).split()[0] == 'start'


def test_missing_tabs_file_falls_back(server, monkeypatch, tmp_path):
    monkeypatch.setenv('XDG_STATE_HOME', str(tmp_path))
    assert host.handle({'tabId': 5, 'owner': 'agent'})['rule'] == 'title'
