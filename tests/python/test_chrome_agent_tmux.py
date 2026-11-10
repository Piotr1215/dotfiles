import importlib.util
import json
import struct
import os
import pty
import shutil
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


def test_native_message_protocol_switches_owned_session(server, tmp_path):
    payload = json.dumps({'owner': 'agent'}).encode()
    result = subprocess.run(
        [str(ROOT / 'scripts/__chrome_agent_tmux.py')],
        input=struct.pack('=I', len(payload)) + payload,
        capture_output=True, check=True, env={**os.environ, 'XDG_STATE_HOME': str(tmp_path)},
    )
    length = struct.unpack('=I', result.stdout[:4])[0]
    assert json.loads(result.stdout[4:4 + length]) == {'switched': True, 'rule': 'title'}
    assert selected(server) == 'agent'
    logged = json.loads((tmp_path / 'agent-tabs/host.log').read_text().splitlines()[-1])
    assert logged['in'] == '{"owner": "agent"}'
    assert logged['out'] == {'switched': True, 'rule': 'title'}


def test_a_miss_logs_the_attached_client_count(server, tmp_path):
    payload = json.dumps({'owner': 'nobody'}).encode()
    subprocess.run(
        [str(ROOT / 'scripts/__chrome_agent_tmux.py')],
        input=struct.pack('=I', len(payload)) + payload,
        capture_output=True, check=True, env={**os.environ, 'XDG_STATE_HOME': str(tmp_path)},
    )
    logged = json.loads((tmp_path / 'agent-tabs/host.log').read_text().splitlines()[-1])
    assert logged['out'] == {'switched': False}
    assert logged['clients'] == 1


def test_host_installer_targets_checkout(tmp_path):
    subprocess.run(
        ['python3', str(ROOT / 'scripts/__chrome_agent_tmux_install.py')],
        env={**os.environ, 'HOME': str(tmp_path)}, check=True,
    )
    manifest = tmp_path / '.config/google-chrome/NativeMessagingHosts/org.piotr.agent_tab_tmux.json'
    data = json.loads(manifest.read_text())
    assert data['path'] == str(ROOT / 'scripts/__chrome_agent_tmux.py')
    assert data['allowed_origins'] == ['chrome-extension://onlalgjmoaahoijjkpdgijadcnihipao/']
    assert manifest.stat().st_mode & 0o777 == 0o600


def test_extension_folder_loads_in_chrome():
    """Chrome rejects an unpacked extension holding any name that starts with "_".

    A __pycache__ there (9 Nov) made Piotr's reload fail and left no extension
    running, so no agent tab switched tmux."""
    folder = ROOT / '.config/chrome-agent-tmux'
    reserved = [str(p.relative_to(folder)) for p in folder.rglob('*') if p.name.startswith('_')]
    assert reserved == []
    assert not list(folder.rglob('*.py'))


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


@pytest.mark.parametrize('owner', ['✅agent', '⌛ agent', '🔴agent'])
def test_title_fallback_reads_past_the_status_symbol(server, tabs, owner):
    """The extension renames a Claude group "✅<agent>"; a stale tab map must still reach the agent."""
    tabs(row(7, '%9999'))
    assert host.handle({'tabId': 7, 'groupTabIds': [7], 'owner': owner}) == {'switched': True, 'rule': 'title'}
    assert current(server).split()[0] == 'agent'


def test_title_fallback_finds_an_agent_in_a_shared_session(server, tabs):
    # Gordon and Kendra run as windows of `task`, so no session carries their name.
    subprocess.run(server + ['new-window', '-t', '=start:'], check=True)
    target = pane_of(server, '=start:1.0')
    subprocess.run(server + ['set-option', '-p', '-t', target, '@agent_name', 'gordon'], check=True)
    subprocess.run(server + ['select-window', '-t', '=start:0'], check=True)
    assert host.handle({'groupTabIds': [5], 'owner': '✅gordon'}) == {'switched': True, 'rule': 'title'}
    assert current(server).split() == ['start', '1', target]


def test_title_fallback_skips_an_ambiguous_or_shared_title(server, tabs):
    for session in ('one', 'two'):
        subprocess.run(server + ['new-session', '-d', '-s', session], check=True)
        subprocess.run(server + ['set-option', '-p', '-t', f'={session}:.0', '@agent_name', 'twin'], check=True)
    assert host.handle({'owner': '✅twin'}) == {'switched': False}
    assert host.handle({'owner': '✅agent, twin'}) == {'switched': False}
    assert host.handle({'owner': '✅'}) == {'switched': False}
    assert current(server).split()[0] == 'start'


def test_no_match(server, tabs):
    assert host.handle({'tabId': 5, 'groupTabIds': [5], 'owner': 'Claude'}) == {'switched': False}
    assert host.handle({'tabId': 5, 'groupTabIds': [], 'owner': ''}) == {'switched': False}
    assert current(server).split()[0] == 'start'


def test_missing_tabs_file_falls_back(server, monkeypatch, tmp_path):
    monkeypatch.setenv('XDG_STATE_HOME', str(tmp_path))
    assert host.handle({'tabId': 5, 'owner': 'agent'})['rule'] == 'title'


def named(tab, agent, session='task', ts=1):
    return {'tab_id': tab, 'pane': '%1', 'session': session, 'agent': agent, 'ts': ts}


def test_names_maps_tabs_to_agents(tabs, monkeypatch):
    monkeypatch.setattr(host, 'run_tmux', lambda *a: pytest.fail('names must not touch tmux'))
    tabs(named(1, 'gordon'), named(2, 'kendra'), named(2, 'triage', ts=5), named(3, '', session='work'),
         named(4, '', session=''), named(5, 'bad\nname', session=''), {'tab_id': '6', 'pane': '%1', 'agent': 'x'})
    reply = host.handle({'op': 'names', 'tabIds': [1, 2, 3, 4, 5, 6, '1', 99]})
    assert reply == {'names': {'1': 'gordon', '2': 'triage', '3': 'work'}}


@pytest.mark.parametrize('ids', [None, 'x', {}])
def test_names_rejects_bad_ids(tabs, ids):
    tabs(named(1, 'gordon'))
    assert host.handle({'op': 'names', 'tabIds': ids}) == {'names': {}}


def test_names_over_native_protocol(tabs):
    tabs(named(7, 'gordon'))
    payload = json.dumps({'op': 'names', 'tabIds': [7]}).encode()
    result = subprocess.run(
        [str(ROOT / 'scripts/__chrome_agent_tmux.py')],
        input=struct.pack('=I', len(payload)) + payload, capture_output=True, check=True,
    )
    length = struct.unpack('=I', result.stdout[:4])[0]
    assert json.loads(result.stdout[4:4 + length]) == {'names': {'7': 'gordon'}}


@pytest.fixture
def extension_copy(tmp_path, monkeypatch):
    monkeypatch.setattr(host, 'run_tmux', lambda *a: pytest.fail('the extension ops must not touch tmux'))
    folder = tmp_path / 'ext'
    shutil.copytree(ROOT / '.config/chrome-agent-tmux', folder)
    monkeypatch.setenv('AGENT_TAB_EXTENSION_DIR', str(folder))
    return folder


def test_extension_dir_defaults_to_the_checkout(monkeypatch):
    monkeypatch.delenv('AGENT_TAB_EXTENSION_DIR', raising=False)
    assert host.extension_dir() == str(ROOT / '.config/chrome-agent-tmux')


def test_check_accepts_the_extension(extension_copy):
    assert host.handle({'op': 'check'}) == {'loadable': True}


def break_reserved(folder):
    (folder / '__pycache__').mkdir()


def break_syntax(folder):
    with open(folder / 'background.js', 'a') as handle:
        handle.write('\nfunction (\n')


def break_manifest(folder):
    (folder / 'manifest.json').write_text('{')


def break_worker_name(folder):
    manifest = json.loads((folder / 'manifest.json').read_text())
    manifest['background']['service_worker'] = 'gone.js'
    (folder / 'manifest.json').write_text(json.dumps(manifest))


@pytest.mark.parametrize('breaker, error', [
    (break_reserved, 'reserved name __pycache__'),
    (break_syntax, 'background.js: SyntaxError'),
    (break_manifest, 'manifest:'),
    (break_worker_name, "manifest: no service worker file 'gone.js'"),
])
def test_check_refuses_a_folder_chrome_would_not_run(extension_copy, breaker, error):
    """The extension reloads itself only when this says the folder loads."""
    breaker(extension_copy)
    reply = host.handle({'op': 'check'})
    assert reply['loadable'] is False
    assert error in reply['error']


def test_check_refuses_without_node(extension_copy, monkeypatch):
    monkeypatch.setattr(host.shutil, 'which', lambda name: None)
    assert host.handle({'op': 'check'}) == {'loadable': False, 'error': 'node not found for the syntax check'}


def test_loaded_only_acknowledges(extension_copy):
    assert host.handle({'op': 'loaded', 'hash': 'abc'}) == {'ok': True}
