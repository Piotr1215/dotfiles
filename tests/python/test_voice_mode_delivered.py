"""Voice mode: the marker the top bar flashes once a line reaches an agent."""
import importlib.util
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('voice_mode', ROOT / 'scripts' / '__voice_mode.py')
voice = importlib.util.module_from_spec(spec)
spec.loader.exec_module(voice)


@pytest.fixture
def marker(monkeypatch, tmp_path):
    path = tmp_path / 'voice-mode-delivered'
    monkeypatch.setattr(voice, 'DELIVERED', str(path))
    monkeypatch.setattr(voice, 'say', lambda _: None)
    monkeypatch.setattr(voice, 'registered', lambda name: name == 'klod2')
    return path


def hear(monkeypatch, heard, delivered=True):
    monkeypatch.setattr(voice, 'transcribe', lambda _: heard)
    monkeypatch.setattr(voice, 'deliver', lambda agent, text: delivered)
    voice.handle(b'')


def test_a_delivered_line_names_the_agent_that_took_it(monkeypatch, marker):
    hear(monkeypatch, 'Claude 2, run the tests')
    assert marker.read_text() == 'klod2'


def test_each_delivery_replaces_the_name(monkeypatch, marker):
    marker.write_text('klod1')
    hear(monkeypatch, 'Claude 2, run the tests')
    assert marker.read_text() == 'klod2'


@pytest.mark.parametrize(('heard', 'delivered'), [
    ('Please pass the salt', True),
    ('Codex, fix the test', True),
    ('Claude 2, yes', False),
], ids=['names no agent', 'no such agent', 'agent not ready'])
def test_a_line_that_reached_nobody_leaves_no_signal(monkeypatch, marker, heard, delivered):
    hear(monkeypatch, heard, delivered)
    assert not marker.exists()
