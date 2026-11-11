import asyncio
import importlib.util
from pathlib import Path

import pytest

path = Path(__file__).resolve().parents[2] / 'scripts/__handoff_tab.py'
spec = importlib.util.spec_from_file_location('handoff_tab', path)
tab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tab)


def test_bridge_sends_url_and_focus(monkeypatch):
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


def test_bridge_reports_rejection(monkeypatch):
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
