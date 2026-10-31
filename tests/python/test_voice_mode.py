"""Voice mode: what gets through from the mic to an agent pane, and what must not."""
import array
import fcntl
import importlib.util
import signal
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('voice_mode', ROOT / 'scripts' / '__voice_mode.py')
voice = importlib.util.module_from_spec(spec)
spec.loader.exec_module(voice)

LOUD = array.array('h', [1000] * 480).tobytes()
QUIET = bytes(960)
RULE = '─' * 40
NBSP = ' '


@pytest.mark.parametrize(('heard', 'agent', 'message'), [
    # Parakeet's real output for "Klod two" and "Klod one" in a Piper voice.
    ('Plot 2. Run the tests.', 'klod2', 'Run the tests.'),
    ('Cloud 1, what are you working on?', 'klod1', 'what are you working on?'),
    ('Claude 2, check the build.', 'klod2', 'check the build.'),
    ('Claude 1. Stop', 'klod1', 'Stop'),
    ('Codex, fix the failing test', 'codex', 'fix the failing test'),
    # Parakeet's real output for Piotr's own spoken "Claude 2, can you hear me?"
    ('Claude too, can you hear me?', 'klod2', 'can you hear me?'),
    ('Claude to, can you hear me?', 'klod2', 'can you hear me?'),
    ('Claude won, stop', 'klod1', 'stop'),
    ('Hey Claude two, look at this', 'klod2', 'look at this'),
    ('klod one: ship it', 'klod1', 'ship it'),
])
def test_named_line_reaches_that_agent(heard, agent, message):
    assert voice.route(heard) == (agent, message)


@pytest.mark.parametrize('heard', [
    'Please pass the salt.',
    'Saying one sentence now for testing',
    'Claude 2',  # a name with nothing to deliver
    'Cloud computing is great',  # no number, ordinary speech about clouds
    'Cloud to edge is cheap',  # a homophone only counts after a real name
    'Plot too thin to finish',
    'Claude is great',
    'Codex is great',  # no pause after the name, so it is talk about Codex
    'The plot 2 twist',  # the name must open the line
    '',
])
def test_unaddressed_speech_is_dropped(heard):
    assert voice.route(heard) is None


def feed(segmenter, frames):
    return [cut for frame in frames if (cut := segmenter.push(frame))]


def test_utterance_ends_after_a_long_silence_and_keeps_the_lead_in():
    lead_in = [QUIET] * voice.PRE_ROLL
    speech = [LOUD] * voice.MIN_VOICED
    tail = [QUIET] * voice.END_FRAMES
    [cut] = feed(voice.Segmenter(), lead_in + speech + tail)
    # The kept window ends on the frame that opened the utterance.
    assert cut == b''.join((lead_in + speech + tail)[voice.START_FRAMES:])


def test_a_pause_inside_a_sentence_does_not_split_it():
    pause = [QUIET] * (voice.END_FRAMES - 1)
    speech = [LOUD] * voice.MIN_VOICED
    tail = [QUIET] * voice.END_FRAMES
    cuts = feed(voice.Segmenter(), speech + pause + speech + tail)
    assert len(cuts) == 1
    assert cuts[0].count(LOUD) >= 2 * voice.MIN_VOICED


def test_a_two_second_thinking_pause_stays_inside_the_line():
    pause = [QUIET] * int(2 / 0.03)
    speech = [LOUD] * voice.MIN_VOICED
    assert len(feed(voice.Segmenter(), speech + pause + speech + [QUIET] * voice.END_FRAMES)) == 1


def test_a_line_with_thinking_pauses_can_run_most_of_a_minute():
    stretch = [LOUD] * 10 + [QUIET] * 60  # speak, then pause for 1.8 s
    assert len(feed(voice.Segmenter(), stretch * 26 + [QUIET] * voice.END_FRAMES)) == 1  # 55 s


def test_a_click_is_too_short_to_be_speech():
    click = [LOUD] * (voice.MIN_VOICED - 1)
    assert feed(voice.Segmenter(), click + [QUIET] * voice.END_FRAMES) == []


def test_two_frames_of_noise_never_open_an_utterance():
    frames = ([LOUD] * (voice.START_FRAMES - 1) + [QUIET]) * 50
    assert feed(voice.Segmenter(), frames + [QUIET] * voice.END_FRAMES) == []


def test_endless_speech_is_cut_at_the_limit():
    cuts = feed(voice.Segmenter(), [LOUD] * (voice.MAX_FRAMES + voice.START_FRAMES))
    assert len(cuts) == 1
    assert len(cuts[0]) == voice.MAX_FRAMES * voice.FRAME_BYTES


def bursts(segmenter, frames):
    found = []
    for frame in frames:
        segmenter.push(frame)
        if burst := segmenter.burst():
            found.append(burst)
    return found


def test_a_short_burst_is_offered_as_soon_as_it_goes_quiet():
    speech = [LOUD] * voice.MIN_VOICED
    quiet = [QUIET] * voice.QUICK_END
    assert bursts(voice.Segmenter(), speech + quiet) == [b''.join(speech + quiet)]


def test_a_burst_is_offered_once_per_pause_and_leaves_the_line_open():
    segmenter = voice.Segmenter()
    speech = [LOUD] * voice.MIN_VOICED
    assert len(bursts(segmenter, speech + [QUIET] * (voice.END_FRAMES - 1))) == 1
    assert len(feed(segmenter, [QUIET])) == 1


def test_a_click_is_never_offered_as_a_burst():
    click = [LOUD] * (voice.MIN_VOICED - 1)
    assert bursts(voice.Segmenter(), click + [QUIET] * voice.QUICK_END) == []


def test_a_long_line_is_never_offered_as_a_burst():
    line = [LOUD] * voice.QUICK_MAX
    assert bursts(voice.Segmenter(), line + [QUIET] * voice.QUICK_END) == []


def claude_box(*rows):
    return '\n'.join(['transcript', RULE, *rows, RULE, '  status line'])


@pytest.mark.parametrize(('capture', 'cursor', 'ready'), [
    (claude_box(f'❯{NBSP}'), 0, True),
    (claude_box(f'❯{NBSP}Press up to edit queued messages'), 0, True),
    (claude_box(f'❯{NBSP}half typed thought'), 0, False),
    (claude_box(f'❯{NBSP}', '  second row of a draft'), 0, False),
    # A permission dialog also opens with the ❯ marker. Enter would approve it.
    (claude_box('❯ 1. Yes', '  2. No'), 0, False),
    (claude_box('Do you want to proceed?', '❯ 1. Yes', '  2. No'), 0, False),
    ('› Ask Codex to do anything\n\n  ? for shortcuts', 0, True),
    ('›\n\n  ? for shortcuts', 0, True),
    ('› half typed thought\n\n  ? for shortcuts', 0, False),
    # An old Codex prompt in the scrollback is not the live composer.
    ('› old prompt\nworking\n', 1, False),
    ('plain shell output', 0, False),
])
def test_composer_ready(capture, cursor, ready):
    assert voice.composer_ready(capture, cursor) is ready


class FakeTmux:
    def __init__(self, composer):
        self.composer = composer
        self.calls = []

    def __call__(self, *args):
        self.calls.append(args)
        if args[0] == 'capture-pane':
            return self.composer
        if args[0] == 'display-message':
            return '0'
        return ''

    def writes(self):
        return [c for c in self.calls if c[0] in ('set-option', 'send-keys')]


def test_deliver_stamps_the_pane_then_types_then_submits_once(monkeypatch):
    fake = FakeTmux(claude_box(f'❯{NBSP}'))
    monkeypatch.setattr(voice, 'tmux', fake)
    assert voice.deliver('%11', 'Piotr to klod2 (voice): run the tests') is True
    stamp, typed, enter = fake.writes()
    assert stamp[:4] == ('set-option', '-p', '-t', '%11')
    assert stamp[4] == '@agent_injected_at'
    assert typed == ('send-keys', '-t', '%11', '-l', '--', 'Piotr to klod2 (voice): run the tests')
    assert enter == ('send-keys', '-t', '%11', 'Enter')


def test_deliver_sends_nothing_to_a_pane_showing_a_dialog(monkeypatch):
    fake = FakeTmux(claude_box('❯ 1. Yes', '  2. No'))
    monkeypatch.setattr(voice, 'tmux', fake)
    monkeypatch.setattr(voice, 'READY_WAIT_SECONDS', 2)
    monkeypatch.setattr(voice.time, 'sleep', lambda _: None)
    assert voice.deliver('%11', 'Piotr to klod2 (voice): yes') is False
    assert fake.writes() == []


def test_panes_maps_agent_names_and_skips_unnamed_panes(monkeypatch):
    listing = {'#{@agent_name} #{pane_id}': ' %1\nklod2 %11\n\nklod1 %37\n'}
    monkeypatch.setattr(voice, 'tmux', lambda *args: listing[args[-1]])
    assert voice.panes() == {'klod2': '%11', 'klod1': '%37'}


def test_silence_ends_speech_and_its_queue_but_nothing_else(monkeypatch):
    monkeypatch.setattr(voice, 'SINK', 'test-sink-for-silence')
    play = 'pw-play --target test-sink-for-silence a.wav'
    spawn = lambda cmdline: subprocess.Popen([cmdline, '30'], executable='sleep')
    speech = [spawn(play), spawn(f'timeout 60 {play}'), spawn(f'flock -w 90 lock timeout 60 {play}')]
    others = [spawn('pw-play --target other-sink a.wav'), spawn(f'zsh -c {play}')]
    try:
        voice.silence()
        assert [process.wait(timeout=5) for process in speech] == [-signal.SIGTERM] * 3
        assert [process.poll() for process in others] == [None, None]
    finally:
        for process in speech + others:
            process.kill()


def test_silence_with_nothing_playing_is_not_an_error(monkeypatch):
    monkeypatch.setattr(voice, 'SINK', 'test-sink-with-no-speech')
    voice.silence()


@pytest.mark.parametrize(('heard', 'stopped'), [
    ('Stop, stop.', True),  # Parakeet's real output for "Stop stop."
    ('stop stop', True),
    ('STOP! STOP!', True),
    ('Stop.', False),
    ('Stop talking.', False),
    ('Stop stop the tests', False),
    ('Please stop, stop it', False),
    ('', False),
])
def test_only_the_whole_stop_word_silences_anything(monkeypatch, capsys, heard, stopped):
    silenced = []
    typed = []
    monkeypatch.setattr(voice, 'transcribe', lambda _: heard)
    monkeypatch.setattr(voice, 'silence', lambda: silenced.append(True))
    monkeypatch.setattr(voice, 'tmux', lambda *args: typed.append(args) or '')
    voice.check_stop(b'')
    assert silenced == ([True] if stopped else [])
    assert typed == []  # speech stops, the agents keep working
    assert capsys.readouterr().out == ('voice-mode: stop word heard\n' if stopped else '')


def test_speaking_follows_the_shared_lock(tmp_path, monkeypatch):
    lock = tmp_path / 'voice.lock'
    monkeypatch.setattr(voice, 'VOICE_LOCK', str(lock))
    assert voice.speaking() is False
    with open(lock, 'a') as held:
        fcntl.flock(held, fcntl.LOCK_EX)
        assert voice.speaking() is True
    assert voice.speaking() is False


class Line:
    """Run handle() with the mic, panes and speech replaced."""

    def __init__(self, monkeypatch, heard, panes, delivered=True):
        self.typed = []
        self.spoken = []
        monkeypatch.setattr(voice, 'transcribe', lambda _: heard)
        monkeypatch.setattr(voice, 'panes', lambda: panes)
        monkeypatch.setattr(voice, 'say', self.spoken.append)
        monkeypatch.setattr(voice, 'deliver', lambda p, t: self.typed.append((p, t)) or delivered)


def test_handle_labels_who_is_talking_to_whom(monkeypatch):
    line = Line(monkeypatch, 'Claude 2, run the tests.', {'klod2': '%11'})
    voice.handle(b'')
    assert line.typed == [('%11', 'Piotr to klod2 (voice): run the tests.')]
    assert line.spoken == []


def test_handle_stays_silent_on_unaddressed_speech(monkeypatch):
    line = Line(monkeypatch, 'Please pass the salt.', {'klod2': '%11'})
    voice.handle(b'')
    assert line.typed == []
    assert line.spoken == []


@pytest.mark.parametrize(('heard', 'logged'), [
    ('Claude 2, run the private tests', 'voice-mode: line sent to klod2\n'),
    ('The private call went fine', 'voice-mode: line names no agent, dropped\n'),
])
def test_handle_logs_the_outcome_but_never_the_words(monkeypatch, capsys, heard, logged):
    Line(monkeypatch, heard, {'klod2': '%11'})
    voice.handle(b'')
    assert capsys.readouterr().out == logged


def test_handle_says_so_when_no_pane_has_that_name(monkeypatch):
    line = Line(monkeypatch, 'Codex, fix the test', {'klod2': '%11'})
    voice.handle(b'')
    assert line.typed == []
    assert line.spoken == ['Voice mode to Piotr. No pane is named codex.']


def test_handle_says_so_when_the_agent_cannot_take_the_line(monkeypatch):
    line = Line(monkeypatch, 'Claude 2, yes', {'klod2': '%11'}, delivered=False)
    voice.handle(b'')
    assert line.spoken == ['Voice mode to Piotr. klod2 is not ready, so that line was dropped.']
