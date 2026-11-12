import asyncio
import importlib.util
from pathlib import Path

import pytest

path = Path(__file__).resolve().parents[2] / 'scripts/__handoff_tab.py'
spec = importlib.util.spec_from_file_location('handoff_tab', path)
tab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tab)

@pytest.fixture(autouse=True)
def production_environment(monkeypatch):
    monkeypatch.delenv('PYTEST_CURRENT_TEST', raising=False)
    monkeypatch.delenv('BATS_TEST_FILENAME', raising=False)
    monkeypatch.delenv('TASKDATA', raising=False)
    monkeypatch.delenv('TASKRC', raising=False)

@pytest.mark.parametrize(('key', 'value'), [
    ('PYTEST_CURRENT_TEST', 'test'), ('BATS_TEST_FILENAME', 'test.bats'),
    ('TASKDATA', '/tmp/isolated-taskdata'), ('TASKRC', '/tmp/isolated-taskrc'),
])
def test_isolated_runs_never_connect(monkeypatch, key, value):
    monkeypatch.delenv('PYTEST_CURRENT_TEST', raising=False)
    monkeypatch.setenv(key, value)
    monkeypatch.setattr(tab, 'RequestClient', lambda *args: pytest.fail('connected'))
    with pytest.raises(RuntimeError, match='suppressed'):
        asyncio.run(tab.open_tab('https://example.com/'))


def test_bridge_sends_url_and_focus(monkeypatch):
    monkeypatch.delenv('PYTEST_CURRENT_TEST', raising=False)
    calls = []
    class Client:
        def __init__(self, socket):
            calls.append(('socket', socket))
        async def connect(self):
            calls.append(('connect',))
        async def request(self, payload):
            calls.append(('request', payload))
            return {'event': 'existing', 'tabId': 42}
        async def close(self):
            calls.append(('close',))
    monkeypatch.setattr(tab, 'RequestClient', Client)
    monkeypatch.setenv('AGENT_BROWSER_NATIVE_SOCKET', '/tmp/test-browser.sock')
    assert asyncio.run(tab.open_tab('https://example.com/', True))['tabId'] == 42
    assert calls[2] == ('request', {'action': 'handoff', 'agent': 'handoffs', 'url': 'https://example.com/', 'focus': True})
    assert calls[-1] == ('close',)


def test_bridge_sends_declared_owner(monkeypatch):
    monkeypatch.delenv('PYTEST_CURRENT_TEST', raising=False)
    requests = []
    class Client:
        def __init__(self, socket): pass
        async def connect(self): pass
        async def request(self, payload):
            requests.append(payload)
            return {'event': 'created'}
        async def close(self): pass
    monkeypatch.setattr(tab, 'RequestClient', Client)
    monkeypatch.setenv('HANDOFF_AGENT', 'agent-one')
    asyncio.run(tab.open_tab('https://example.com/'))
    assert requests[0]['agent'] == 'agent-one'


def test_bridge_reports_rejection(monkeypatch):
    monkeypatch.delenv('PYTEST_CURRENT_TEST', raising=False)
    class Client:
        def __init__(self, socket): pass
        async def connect(self): pass
        async def request(self, payload): return {'event': 'error'}
        async def close(self): pass
    monkeypatch.setattr(tab, 'RequestClient', Client)
    monkeypatch.setenv('AGENT_BROWSER_NATIVE_SOCKET', '/tmp/test-browser.sock')
    with pytest.raises(RuntimeError, match='could not open'):
        asyncio.run(tab.open_tab('https://example.com/'))


@pytest.mark.parametrize('url', ['http://example.com/', 'https://user@example.com/',
                                  'https://example.com:443/', 'https://example.com/\n'])
def test_rejects_ambiguous_url_before_connecting(monkeypatch, url):
    monkeypatch.delenv('PYTEST_CURRENT_TEST', raising=False)
    monkeypatch.setattr(tab, 'RequestClient', lambda *args: pytest.fail('connected'))
    with pytest.raises(ValueError):
        asyncio.run(tab.open_tab(url))


def test_timeout_names_the_unresponsive_bridge(monkeypatch, capsys):
    async def timeout(*args):
        raise asyncio.TimeoutError()
    monkeypatch.setattr(tab, 'open_tab', timeout)
    monkeypatch.setattr(tab.sys, 'argv', ['handoff-tab', 'https://example.com/'])
    assert tab.main() == 1
    assert 'browser bridge did not respond' in capsys.readouterr().err
