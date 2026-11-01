"""Voice mode: what the relay leaves for the top bar to blink after each line."""
import importlib.util
import queue
import threading
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('voice_mode', ROOT / 'scripts' / '__voice_mode.py')
voice = importlib.util.module_from_spec(spec)
spec.loader.exec_module(voice)


@pytest.fixture(autouse=True)
def no_earlier_line(monkeypatch, tmp_path):
    monkeypatch.setattr(voice, 'CHANNEL', str(tmp_path / 'channel'))
    monkeypatch.setattr(voice, 'moved_on', lambda _: None)


@pytest.fixture
def marker(monkeypatch, tmp_path):
    path = tmp_path / 'voice-mode-line'
    monkeypatch.setattr(voice, 'LINE_STATUS', str(path))
    monkeypatch.setattr(voice, 'say', lambda _: None)
    monkeypatch.setattr(voice, 'registered', lambda name: name == 'klod2')
    return path


def hear(monkeypatch, heard, published=True):
    monkeypatch.setattr(voice, 'transcribe', lambda _: heard)
    monkeypatch.setattr(voice, 'deliver', lambda agent, text: published)
    voice.handle(b'')


@pytest.mark.parametrize(('heard', 'published', 'status'), [
    ('Claude 2, run the tests', True, 'sent'),
    ('Please pass the salt', True, 'dropped'),
    ('Claw 2, run the tests', True, 'dropped'),
    ('Codex, fix the test', True, 'failed'),
    ('Claude 2, yes', False, 'failed'),
], ids=['bus took it', 'names no agent', 'misheard name', 'no such agent', 'publish failed'])
def test_each_line_leaves_its_outcome(monkeypatch, marker, heard, published, status):
    hear(monkeypatch, heard, published)
    assert marker.read_text() == status


def test_the_latest_line_replaces_the_last_outcome(monkeypatch, marker):
    marker.write_text('failed')
    hear(monkeypatch, 'Claude 2, run the tests')
    assert marker.read_text() == 'sent'


def test_the_stop_word_is_not_a_dropped_line(monkeypatch, marker, capsys):
    marker.write_text('sent')
    hear(monkeypatch, 'Stop, stop.')
    assert marker.read_text() == 'sent'
    assert 'dropped' not in capsys.readouterr().out


def test_a_line_that_came_back_with_no_words_is_not_lost_in_silence(monkeypatch, marker):
    hear(monkeypatch, '  ')
    assert marker.read_text() == 'dropped'


@pytest.mark.parametrize(('heard', 'still_talking', 'status'), [
    ('Check check Claw two run', True, 'armed'),
    ('Check, check. Claw two', True, 'armed'),
    ('Please pass the salt', True, None),
    ('Let me check check the', True, None),
    ('Check check Claw two run', False, None),
], ids=['opens with it', 'with a pause', 'room talk', 'said inside a sentence', 'line already closed'])
def test_the_light_turns_yellow_only_for_a_live_line_that_opens_with_the_wake_word(
        monkeypatch, marker, heard, still_talking, status):
    monkeypatch.setattr(voice, 'transcribe', lambda _: heard)
    segmenter = voice.Segmenter()
    segmenter.utterance = [b''] if still_talking else None
    voice.check_wake(b'', segmenter, voice.BargeIn())
    assert (marker.read_text() if marker.exists() else None) == status


def test_an_opening_that_cannot_be_transcribed_shows_nothing(monkeypatch, marker):
    def broken(_):
        raise voice.subprocess.CalledProcessError(1, 'handy')

    monkeypatch.setattr(voice, 'transcribe', broken)
    segmenter = voice.Segmenter()
    segmenter.utterance = [b'']
    voice.check_wake(b'', segmenter, voice.BargeIn())
    assert not marker.exists()


def test_a_clip_that_cannot_be_transcribed_shows_as_failed(monkeypatch, marker):
    def broken(_):
        raise ValueError('no transcript')

    done = threading.Event()
    clips = queue.Queue()
    clips.put(b'')
    monkeypatch.setattr(voice, 'signal', lambda status: (marker.write_text(status), done.set()))
    threading.Thread(target=voice.worker, args=(clips, broken), daemon=True).start()
    assert done.wait(2)
    assert marker.read_text() == 'failed'
