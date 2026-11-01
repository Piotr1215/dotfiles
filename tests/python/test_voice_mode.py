"""Voice mode: what gets through from the mic to an agent pane, and what must not."""
import array
import importlib.util
import io
import json
import math
import os
import random
import signal
import subprocess
import sys
import threading
import time
import types
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('voice_mode', ROOT / 'scripts' / '__voice_mode.py')
voice = importlib.util.module_from_spec(spec)
spec.loader.exec_module(voice)

OPEN_MIC = voice.Segmenter  # as the relay starts: it has heard no room yet


class QuietRoom(voice.Segmenter):
    """A mic that was silent a moment ago, so a line can open on the first frame."""

    def __init__(self):
        super().__init__()
        self.levels.append(0.0)


def tone(level):
    return array.array('h', [level, -level] * 240).tobytes()


def room(level, frames):
    """Steady room noise, the same every run."""
    noise = random.Random(7)
    return [array.array('h', [int(noise.gauss(0, level)) for _ in range(480)]).tobytes() for _ in range(frames)]


def talking(frames):
    """Speech with the short gaps real speech has, which show the room behind it."""
    return (([LOUD] * 99 + [QUIET]) * (frames // 100 + 1))[:frames]


LOUD = tone(1000)
QUIET = bytes(960)


@pytest.fixture(autouse=True)
def fresh_relay(monkeypatch, tmp_path):
    """No test inherits an earlier line's agent, or touches the real lost lines and flags."""
    monkeypatch.setattr(voice, 'LATEST', {})
    monkeypatch.setattr(voice, 'LOST_DIR', str(tmp_path / 'lost'))
    monkeypatch.setattr(voice, 'NO_KEEP', str(tmp_path / 'no-keep'))
    monkeypatch.setattr(voice, 'NO_CONTINUE', str(tmp_path / 'no-continue'))
    monkeypatch.setattr(voice, 'Segmenter', QuietRoom)


@pytest.mark.parametrize(('heard', 'agent', 'message'), [
    # Parakeet's real output for "Klod two" and "Klod one" in a Piper voice.
    ('Plot 2. Run the tests.', 'klod2', 'Run the tests.'),
    ('Cloud 1, what are you working on?', 'klod1', 'what are you working on?'),
    ('Claude 2, check the build.', 'klod2', 'check the build.'),
    ('Claude 1. Stop', 'klod1', 'Stop'),
    ('Codex, fix the failing test', 'codex', 'fix the failing test'),
    # Gordon and Kendra answer on the bus as triage and intake.
    ('Gordon, what is on my list?', 'triage', 'what is on my list?'),
    ('Hey Gordon, look at this.', 'triage', 'look at this.'),
    ('Kendra, check the inbox', 'intake', 'check the inbox'),
    # Parakeet's real output for Piotr's own spoken "Claude 2, can you hear me?"
    ('Claude too, can you hear me?', 'klod2', 'can you hear me?'),
    ('Claude to, can you hear me?', 'klod2', 'can you hear me?'),
    ('Claude won, stop', 'klod1', 'stop'),
    ('Hey Claude two, look at this', 'klod2', 'look at this'),
    ('klod one: ship it', 'klod1', 'ship it'),
    # The stop word and a line said before the quiet could close it.
    ('Stop, stop. Claude 2, run the tests.', 'klod2', 'run the tests.'),
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
    'Claude 1 to Piotr: the tests pass',  # an agent's own speech caught by the mic
    'Cloud 2 to Peter. The build is green.',
    'Gordon is out today',
    'Kendra said no',
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


def test_room_noise_on_an_open_mic_opens_no_line():
    segmenter = OPEN_MIC()
    assert feed(segmenter, room(4000, 300)) == []
    assert segmenter.utterance is None


def test_speech_over_room_noise_is_one_line():
    frames = room(3000, 60) + [tone(15000)] * voice.MIN_VOICED * 3 + room(3000, voice.END_FRAMES)
    assert len(feed(OPEN_MIC(), frames)) == 1


@pytest.mark.parametrize(('over_margin', 'cuts'), [(-0.5, 0), (0.5, 1)], ids=['under', 'over'])
def test_speech_has_to_clear_the_room_by_the_margin(over_margin, cuts):
    speech = tone(int(4000 * (voice.NOISE_MARGIN + over_margin)))
    frames = [tone(4000)] * 60 + [speech] * voice.MIN_VOICED + [tone(4000)] * voice.END_FRAMES
    assert len(feed(OPEN_MIC(), frames)) == cuts


def test_a_room_that_turns_loud_becomes_the_new_room():
    segmenter = OPEN_MIC()
    feed(segmenter, [QUIET] * 5 + room(4000, voice.NOISE_WINDOW + voice.END_FRAMES + 10))
    assert segmenter.utterance is None


def test_a_faint_sound_on_a_silent_mic_stays_under_the_speech_level():
    assert feed(voice.Segmenter(), [tone(50)] * 50 + [QUIET] * voice.END_FRAMES) == []


def test_rumble_below_speech_opens_no_line_on_a_silent_mic():
    wave = [int(300 * math.sin(2 * math.pi * 30 * n / voice.RATE)) for n in range(480 * 60)]
    rumble = [array.array('h', wave[start:start + 480]).tobytes() for start in range(0, len(wave), 480)]
    assert feed(voice.Segmenter(), rumble + [QUIET] * voice.END_FRAMES) == []


def test_speech_plays_on_the_default_output(monkeypatch):
    played = []
    monkeypatch.setattr(voice.subprocess, 'run', lambda argv, **_: played.append(argv))
    voice.say('hello')
    assert played[-1][:4] == ['flock', voice.VOICE_LOCK, 'timeout', '30']
    assert played[-1][4:-1] == voice.PLAYER.split()
    assert '--target' not in played[-1]


def test_a_click_is_too_short_to_be_speech():
    click = [LOUD] * (voice.MIN_VOICED - 1)
    assert feed(voice.Segmenter(), click + [QUIET] * voice.END_FRAMES) == []


def test_two_frames_of_noise_never_open_an_utterance():
    frames = ([LOUD] * (voice.START_FRAMES - 1) + [QUIET]) * 50
    assert feed(voice.Segmenter(), frames + [QUIET] * voice.END_FRAMES) == []


def test_endless_speech_is_cut_at_the_limit():
    cuts = feed(voice.Segmenter(), talking(voice.MAX_FRAMES + voice.START_FRAMES))
    assert len(cuts) == 1
    assert len(cuts[0]) == voice.MAX_FRAMES * voice.FRAME_BYTES


def bursts(segmenter, frames):
    found = []
    for frame in frames:
        segmenter.push(frame)
        if burst := segmenter.burst():
            found.append(burst)
    return found


def test_a_line_offers_its_opening_once_while_it_is_still_going():
    segmenter = voice.Segmenter()
    offered = []
    for frame in [LOUD] * (voice.OPENING_FRAMES * 3):
        segmenter.push(frame)
        if opening := segmenter.opening():
            offered.append(opening)
    assert len(offered) == 1
    assert len(offered[0]) == voice.OPENING_FRAMES * len(LOUD)


def test_a_click_offers_no_opening():
    segmenter = voice.Segmenter()
    offered = []
    for frame in [LOUD] * (voice.MIN_VOICED - 1) + [QUIET] * voice.END_FRAMES:
        segmenter.push(frame)
        offered.append(segmenter.opening())
    assert not any(offered)


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


def test_silence_ends_speech_and_its_queue_but_nothing_else(monkeypatch):
    monkeypatch.setattr(voice, 'PLAYER', 'pw-play -P media.name=test-silence')
    play = 'pw-play -P media.name=test-silence a.wav'
    spawn = lambda cmdline: subprocess.Popen([cmdline, '30'], executable='sleep')
    speech = [spawn(play), spawn(f'timeout 60 {play}'), spawn(f'flock -w 90 lock timeout 60 {play}')]
    others = [spawn('pw-play -P media.name=test-other a.wav'), spawn(f'zsh -c {play}')]
    try:
        voice.silence()
        assert [process.wait(timeout=5) for process in speech] == [-signal.SIGTERM] * 3
        assert [process.poll() for process in others] == [None, None]
    finally:
        for process in speech + others:
            process.kill()


def test_silence_with_nothing_playing_is_not_an_error(monkeypatch):
    monkeypatch.setattr(voice, 'PLAYER', 'pw-play -P media.name=test-nothing-playing')
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
    monkeypatch.setattr(voice, 'deliver', lambda *args: typed.append(args))
    voice.check_stop(b'')
    assert silenced == ([True] if stopped else [])
    assert typed == []  # speech stops, the agents keep working
    assert capsys.readouterr().out == ('voice-mode: stop word heard\n' if stopped else '')


class Line:
    """Run handle() with the mic, bus and speech replaced."""

    def __init__(self, monkeypatch, heard, agents, delivered=True):
        self.sent = []
        self.spoken = []
        monkeypatch.setattr(voice, 'transcribe', lambda _: heard)
        monkeypatch.setattr(voice, 'registered', lambda name: name in agents)
        monkeypatch.setattr(voice, 'say', self.spoken.append)
        monkeypatch.setattr(voice, 'deliver', lambda a, t: self.sent.append((a, t)) or delivered)
        monkeypatch.setattr(voice, 'LINE_STATUS', os.devnull)  # the live marker flashes the panel


def test_handle_labels_who_is_talking_to_whom(monkeypatch):
    line = Line(monkeypatch, 'Claude 2, run the tests.', {'klod2'})
    voice.handle(b'')
    assert line.sent == [('klod2', '[PIOTR VIA VOICE] Piotr to klod2: run the tests. '
                          '(Local transcript, can be misheard. Answer in your chat. '
                          'Confirm anything destructive with him first.)')]
    assert line.spoken == []


def test_handle_stays_silent_on_unaddressed_speech(monkeypatch):
    line = Line(monkeypatch, 'Please pass the salt.', {'klod2'})
    voice.handle(b'')
    assert line.sent == []
    assert line.spoken == []


@pytest.mark.parametrize(('heard', 'logged'), [
    ('Claude 2, run the private tests', 'voice-mode: line sent to klod2\n'),
    ('The private call went fine', 'voice-mode: line names no agent, dropped\n'),
])
def test_handle_logs_the_outcome_but_never_the_words(monkeypatch, capsys, heard, logged):
    Line(monkeypatch, heard, {'klod2'})
    voice.handle(b'')
    assert capsys.readouterr().out == logged


def test_handle_says_so_when_no_agent_has_that_name(monkeypatch):
    line = Line(monkeypatch, 'Codex, fix the test', {'klod2'})
    voice.handle(b'')
    assert line.sent == []
    assert line.spoken == ['Voice mode to Piotr. No agent is registered as codex.']


def test_handle_says_so_when_the_agent_cannot_take_the_line(monkeypatch):
    line = Line(monkeypatch, 'Claude 2, yes', {'klod2'}, delivered=False)
    voice.handle(b'')
    assert line.spoken == ['Voice mode to Piotr. klod2 did not get that line.']


def beat(name):
    return json.dumps({'agent_id': f'{name}-1', 'name': name, 'group': 'default', 'host': 'serval', 'ts': 1})


def test_an_agent_is_registered_only_while_its_beats_arrive(monkeypatch):
    clock = [1000.0]
    monkeypatch.setattr(voice.time, 'monotonic', lambda: clock[0])
    presence = voice.Presence()
    assert presence.has('klod2') is False
    presence.beat(beat('klod2'))
    clock[0] += voice.PEER_TTL_SECONDS - 1
    assert presence.has('klod2') is True
    clock[0] += 1
    assert presence.has('klod2') is False


@pytest.mark.parametrize('noise', ['', 'Subscribing on agents.presence', '[1]', '{"host": "serval"}'])
def test_anything_but_a_beat_registers_nobody(noise):
    presence = voice.Presence()
    presence.beat(noise)
    assert presence.last_beat == {}


def test_a_line_goes_out_as_a_bus_dm_never_marked_human(monkeypatch):
    calls = []

    def published(command, **options):
        calls.append((command, options))
        return subprocess.CompletedProcess(command, 0)

    monkeypatch.setattr(voice.subprocess, 'run', published)
    assert voice.deliver('klod2', 'the line') is True
    [(command, options)] = calls
    assert command == ['node', voice.SND, 'klod2', 'the line']
    assert options['env']['SND_FROM'] == 'human-via-voice'
    assert options['env']['AGENTS_NATS_URL'] == voice.NATS_URL


def refused(command, **_):
    return subprocess.CompletedProcess(command, 2)


def timed_out(command, **_):
    raise subprocess.TimeoutExpired(command, voice.SND_TIMEOUT_SECONDS)


@pytest.mark.parametrize('failure', [refused, timed_out])
def test_a_publish_that_fails_is_not_called_delivered(monkeypatch, failure):
    monkeypatch.setattr(voice.subprocess, 'run', failure)
    assert voice.deliver('klod2', 'the line') is False


class Model:
    """The live roster, and a stand-in for the quick decision model that records what it is shown."""

    def __init__(self, monkeypatch, agents, choice='klod two', probability=0.9):
        self.calls = []
        presence = voice.Presence()
        for agent in agents:
            presence.beat(beat(agent))
        monkeypatch.setattr(voice, 'PRESENCE', presence)

        def decided(command, **options):
            self.calls.append((command, options))
            picked = choice if isinstance(choice, str) else next(
                name for words, name in choice.items() if words in options['input'])
            answer = {'choice': picked, 'probabilities': {picked: probability}}
            return subprocess.CompletedProcess(command, 0, stdout=json.dumps({'answers': {'q': answer}}))

        monkeypatch.setattr(voice.subprocess, 'run', decided)

    def openings(self):
        return [options['input'] for _, options in self.calls]

    def options(self):
        [(command, _)] = self.calls
        return set(command[command.index('-c') + 1].split(','))


@pytest.mark.parametrize(('agent', 'said'), [
    ('klod2', 'klod two'),
    ('codex', 'codex'),
    ('devops-1673', 'devops one six seven three'),
    ('doc-42', 'doc four two'),
    ('triage', 'gordon'),
    ('intake', 'kendra'),
])
def test_a_name_is_offered_as_it_is_said_aloud(agent, said):
    assert voice.spoken(agent) == said


@pytest.mark.parametrize('heard', [
    'Check check Claw two, run the tests.',
    'Check, check. Claw two, run the tests.',
    'CHECK-CHECK: Claw two, run the tests.',
    'Stop, stop. Check, check. Claw two, run the tests.',
])
def test_the_wake_word_sends_the_line_to_the_name_it_sounds_like(monkeypatch, heard):
    line = Line(monkeypatch, heard, {'klod2'})
    Model(monkeypatch, ['klod1', 'klod2', 'codex'])
    voice.handle(b'')
    [(agent, text)] = line.sent
    assert agent == 'klod2'
    assert text.startswith('[PIOTR VIA VOICE] Piotr to klod2: Claw two, run the tests. (Local transcript')


def test_the_model_sees_the_live_roster_and_only_the_opening_words(monkeypatch):
    words = ' '.join(f'word{n}' for n in range(voice.FIT_WORDS + 3))
    Line(monkeypatch, f'check check {words}', {'klod2'})
    model = Model(monkeypatch, ['klod2', 'codex', 'devops-1673', 'human-via-signal'])
    voice.handle(b'')
    [(command, options)] = model.calls
    assert model.options() == {'klod two', 'codex', 'devops one six seven three', 'gordon', 'kendra'}
    assert options['input'] == ' '.join(words.split()[:voice.FIT_WORDS])
    assert 'word0' not in ' '.join(command)  # argv reaches error messages, and the relay logs no words


def test_an_agent_that_left_the_bus_is_not_offered(monkeypatch):
    clock = [1000.0]
    monkeypatch.setattr(voice.time, 'monotonic', lambda: clock[0])
    Line(monkeypatch, 'check check claw two, go', {'klod2'})
    model = Model(monkeypatch, ['klod1', 'klod2'])
    clock[0] += voice.PEER_TTL_SECONDS
    voice.PRESENCE.beat(beat('klod2'))
    voice.handle(b'')
    assert 'klod one' not in model.options()


def test_gordon_away_gets_the_notice_not_the_nearest_agent(monkeypatch):
    line = Line(monkeypatch, 'check check Gordon, what is on my list?', {'klod2'})
    Model(monkeypatch, ['klod2'], choice='gordon')
    voice.handle(b'')
    assert line.sent == []
    assert line.spoken == ['Voice mode to Piotr. No agent is registered as triage.']


@pytest.mark.parametrize(('probability', 'sent'), [(voice.FIT_FLOOR, 1), (voice.FIT_FLOOR - 0.01, 0)])
def test_a_name_that_sounds_like_nobody_goes_nowhere(monkeypatch, tmp_path, probability, sent):
    line = Line(monkeypatch, 'check check reviewer, look at this', {'klod2'})
    monkeypatch.setattr(voice, 'LINE_STATUS', str(tmp_path / 'status'))
    Model(monkeypatch, ['klod2'], probability=probability)
    voice.handle(b'')
    assert len(line.sent) == sent
    assert (tmp_path / 'status').read_text() == ('sent' if sent else 'dropped')


@pytest.mark.parametrize('heard', [
    'Please pass the salt.',
    'Claw two, run the tests.',  # no wake word, so it stays on this machine
    'Claude 2, run the tests.',  # an exact name needs no model
    'Let me check check the build.',  # the wake word must open the line
    'Check, check.',  # nothing after it to send
])
def test_nothing_reaches_the_model_without_the_wake_word_and_a_line(monkeypatch, heard):
    Line(monkeypatch, heard, {'klod2'})
    model = Model(monkeypatch, ['klod2'])
    voice.handle(b'')
    assert model.calls == []


CALLS = {'Claw one': 'klod one', 'Codex': 'codex', 'clause two': 'klod two'}


def said_to(line):
    return [(agent, text.split(': ', 1)[1].split(' (Local')[0]) for agent, text in line.sent]


@pytest.mark.parametrize('heard', [
    'Check check Claw one, do X. Check check Codex do Y. Check check clause two do Z.',
    'Check, check, Claw one, do X. Check, check. Codex do Y. Check check: clause two do Z.',
])
def test_one_line_reaches_each_agent_it_calls(monkeypatch, heard):
    line = Line(monkeypatch, heard, {'klod1', 'klod2', 'codex'})
    model = Model(monkeypatch, ['klod1', 'klod2', 'codex'], choice=CALLS)
    voice.handle(b'')
    assert said_to(line) == [('klod1', 'Claw one, do X.'), ('codex', 'Codex do Y.'), ('klod2', 'clause two do Z.')]
    assert model.openings() == ['Claw one, do X.', 'Codex do Y.', 'clause two do Z.']


def test_a_comma_before_the_next_call_stays_out_of_the_message(monkeypatch):
    line = Line(monkeypatch, 'check check Claw one do X, check check Codex do Y', {'klod1', 'codex'})
    Model(monkeypatch, ['klod1', 'codex'], choice=CALLS)
    voice.handle(b'')
    assert said_to(line) == [('klod1', 'Claw one do X'), ('codex', 'Codex do Y')]


def test_a_named_line_can_call_the_next_agent_too(monkeypatch):
    line = Line(monkeypatch, 'Gordon, do X. Check check Codex do Y.', {'triage', 'codex'})
    model = Model(monkeypatch, ['codex'], choice=CALLS)
    voice.handle(b'')
    assert said_to(line) == [('triage', 'do X.'), ('codex', 'Codex do Y.')]
    assert model.openings() == ['Codex do Y.']


def test_the_phrase_said_inside_a_sentence_stays_in_the_line(monkeypatch, tmp_path):
    # Piotr's own lines at 23:58 and 23:59 lost everything from the phrase onwards.
    line = Line(monkeypatch, 'Claude 1, turn the dot yellow after the words check check are heard', {'klod1'})
    Model(monkeypatch, ['klod1'], probability=voice.FIT_FLOOR - 0.01)
    monkeypatch.setattr(voice, 'LINE_STATUS', str(tmp_path / 'status'))
    voice.handle(b'')
    assert said_to(line) == [('klod1', 'turn the dot yellow after the words check check are heard')]


def test_a_trailing_wake_word_adds_no_call(monkeypatch):
    line = Line(monkeypatch, 'check check Codex do Y. Check check.', {'codex'})
    Model(monkeypatch, ['codex'], choice=CALLS)
    voice.handle(b'')
    assert said_to(line) == [('codex', 'Codex do Y.')]


def test_a_failed_decision_sends_none_of_the_line(monkeypatch):
    line = Line(monkeypatch, 'check check Claw one do X check check Codex do Y', {'klod1', 'codex'})
    model = Model(monkeypatch, ['klod1', 'codex'], choice='not on the roster')
    with pytest.raises(KeyError):
        voice.handle(b'')
    assert line.sent == []
    assert len(model.calls) == 1


@pytest.mark.parametrize(('agents', 'delivered', 'probability', 'status'), [
    ({'klod1', 'codex'}, True, 0.9, 'sent'),
    ({'klod1'}, True, 0.9, 'failed'),  # one of them is not on the bus
    ({'klod1', 'codex'}, False, 0.9, 'failed'),
    ({'klod1', 'codex'}, True, 0.5, 'dropped'),
])
def test_the_light_shows_the_worst_call_of_the_line(monkeypatch, tmp_path, agents, delivered, probability, status):
    Line(monkeypatch, 'check check Claw one do X check check Codex do Y', agents, delivered=delivered)
    monkeypatch.setattr(voice, 'LINE_STATUS', str(tmp_path / 'status'))
    Model(monkeypatch, ['klod1', 'codex'], choice=CALLS, probability=probability)
    voice.handle(b'')
    assert (tmp_path / 'status').read_text() == status


def test_words_after_a_weak_name_stay_in_the_call_before_them(monkeypatch, tmp_path):
    line = Line(monkeypatch, 'Gordon, do X. Check check reviewer do Y.', {'triage'})
    monkeypatch.setattr(voice, 'LINE_STATUS', str(tmp_path / 'status'))
    Model(monkeypatch, ['klod1'], probability=0.5)
    voice.handle(b'')
    assert said_to(line) == [('triage', 'do X. check check reviewer do Y.')]


def test_every_weak_name_stays_in_the_one_real_call(monkeypatch):
    line = Line(monkeypatch, 'Gordon, do X. Check check reviewer do Y. Check check planner do Z.', {'triage'})
    Model(monkeypatch, ['klod1'], probability=0.5)
    voice.handle(b'')
    assert said_to(line) == [('triage', 'do X. check check reviewer do Y. check check planner do Z.')]


def test_a_call_that_found_nobody_is_orange_though_its_words_arrived(monkeypatch, tmp_path):
    # Green here would read as reviewer got it, and the light exists to show that loss.
    Line(monkeypatch, 'Gordon, do X. Check check reviewer do Y.', {'triage'})
    monkeypatch.setattr(voice, 'LINE_STATUS', str(tmp_path / 'status'))
    Model(monkeypatch, ['klod1'], probability=0.5)
    voice.handle(b'')
    assert (tmp_path / 'status').read_text() == 'dropped'


def test_a_failed_call_outranks_a_dropped_one_on_the_light(monkeypatch, tmp_path):
    Line(monkeypatch, 'Check check reviewer do X. Check check Gordon do Y.', set())
    monkeypatch.setattr(voice, 'LINE_STATUS', str(tmp_path / 'status'))
    monkeypatch.setattr(voice, 'closest', lambda part: 'triage' if 'Gordon' in part else None)
    voice.handle(b'')
    assert (tmp_path / 'status').read_text() == 'failed'


def test_a_failed_decision_carries_no_words_to_the_log(monkeypatch):
    def failed(command, **options):
        raise subprocess.CalledProcessError(1, command)

    Line(monkeypatch, 'check check klod two, the private thing', {'klod2'})
    Model(monkeypatch, ['klod2'])
    monkeypatch.setattr(voice.subprocess, 'run', failed)
    with pytest.raises(subprocess.SubprocessError) as err:
        voice.handle(b'')
    assert 'private' not in str(err.value)


class Held:
    """Record what BargeIn asks of the speech playing."""

    def __init__(self, monkeypatch, tmp_path):
        self.calls = []
        self.flag = tmp_path / 'no-barge-in'
        monkeypatch.setattr(voice, 'hold_speech', self.calls.append)
        monkeypatch.setattr(voice, 'NO_BARGE_IN', str(self.flag))


def test_speech_pauses_when_piotr_starts_and_carries_on_when_he_ends(monkeypatch, tmp_path):
    held = Held(monkeypatch, tmp_path)
    barge_in = voice.BargeIn()
    for talking in (False, True, True, False, False):
        barge_in.update(talking)
    assert held.calls == [True, False]


def test_a_reply_that_starts_while_he_talks_is_paused_too(monkeypatch, tmp_path):
    held = Held(monkeypatch, tmp_path)
    barge_in = voice.BargeIn()
    for _ in range(voice.HOLD_FRAMES + 1):
        barge_in.update(True)
    assert held.calls == [True, True]


def test_the_toggle_off_leaves_speech_alone(monkeypatch, tmp_path):
    held = Held(monkeypatch, tmp_path)
    held.flag.touch()
    barge_in = voice.BargeIn()
    for talking in (True, True, False):
        barge_in.update(talking)
    assert held.calls == []


def test_switching_off_mid_line_lets_speech_carry_on(monkeypatch, tmp_path):
    held = Held(monkeypatch, tmp_path)
    barge_in = voice.BargeIn()
    barge_in.update(True)
    held.flag.touch()
    barge_in.update(True)
    assert held.calls == [True, False]


def run_state(process):
    with open(f'/proc/{process.pid}/stat', encoding='utf-8') as stat:
        return stat.read().rsplit(')', 1)[1].split()[0]


def settled(process, wanted):
    """The process's state once it reaches wanted, or as it stands after a second."""
    deadline = time.monotonic() + 1
    while run_state(process) != wanted and time.monotonic() < deadline:
        time.sleep(0.01)
    return run_state(process)


def test_a_hold_pauses_only_the_player_and_the_release_wakes_it(monkeypatch):
    monkeypatch.setattr(voice, 'PLAYER', 'pw-play -P media.name=test-hold')
    play = 'pw-play -P media.name=test-hold a.wav'
    spawn = lambda cmdline: subprocess.Popen([cmdline, '30'], executable='sleep')
    player, wrapper, other = spawn(play), spawn(f'timeout 60 {play}'), spawn('pw-play -P media.name=test-other a.wav')
    try:
        voice.hold_speech(True)
        assert settled(player, 'T') == 'T'
        assert 'T' not in (run_state(wrapper), run_state(other))
        voice.hold_speech(False)
        assert settled(player, 'S') != 'T'
    finally:
        for process in (player, wrapper, other):
            process.kill()


def test_the_stop_word_still_ends_paused_speech(monkeypatch):
    monkeypatch.setattr(voice, 'PLAYER', 'pw-play -P media.name=test-paused-stop')
    player = subprocess.Popen(['pw-play -P media.name=test-paused-stop a.wav', '30'], executable='sleep')
    try:
        voice.hold_speech(True)
        settled(player, 'T')
        voice.silence()
        assert player.wait(timeout=5) == -signal.SIGTERM
    finally:
        player.kill()


def test_the_relay_holds_speech_for_the_length_of_a_line(monkeypatch, tmp_path):
    held = Held(monkeypatch, tmp_path)
    frames = LOUD * voice.MIN_VOICED + QUIET * voice.END_FRAMES
    monkeypatch.setattr(voice.subprocess, 'Popen', lambda *_, **__: types.SimpleNamespace(stdout=io.BytesIO(frames)))
    monkeypatch.setattr(voice.threading, 'Thread', lambda **_: types.SimpleNamespace(start=lambda: None))
    with pytest.raises(SystemExit):
        voice.main()
    assert held.calls[:2] == [False, True]  # a relay that died mid-line left speech paused
    assert held.calls[-1] is False
    assert held.calls.count(False) == 2


# Words must not vanish. Measured on the real path before this: 147 s of speech cut into
# 60, 60 and 29 s and only the first piece reached an agent; 361 s the same, Handy 3.5 s.

MINUTE = bytes(2 * voice.RATE * 60)


def lost_files():
    folder = Path(voice.LOST_DIR)
    return sorted(path.name[-4:] for path in folder.iterdir()) if folder.exists() else []


def test_a_two_minute_line_stays_one_line():
    cuts = feed(voice.Segmenter(), talking(int(120 / 0.03)) + [QUIET] * voice.END_FRAMES)
    assert len(cuts) == 1
    assert len(cuts[0]) >= len(MINUTE) * 2


def test_a_line_that_never_ends_still_closes(monkeypatch):
    monkeypatch.setattr(voice, 'MAX_FRAMES', 50)
    assert len(feed(voice.Segmenter(), [LOUD] * 120)) == 2


class Handy:
    """Stands in for the Handy binary: notes how long each clip was, and fails on request."""

    def __init__(self, monkeypatch, failures=0):
        self.clips, self.failures = [], failures
        self.running = self.most = 0
        monkeypatch.setattr(voice.subprocess, 'run', self.run)
        monkeypatch.setattr(voice.time, 'sleep', lambda _: None)

    def run(self, command, **_):
        self.running += 1
        self.most = max(self.most, self.running)
        with voice.wave.open(command[2], 'rb') as clip:
            self.clips.append(clip.getnframes() / voice.RATE)
        threading.Event().wait(0.01)
        self.running -= 1
        if self.failures:
            self.failures -= 1
            raise subprocess.CalledProcessError(1, command)
        return subprocess.CompletedProcess(command, 0, stdout=json.dumps({'text': f'part{len(self.clips)}'}))


def test_a_long_line_reaches_handy_in_pieces_and_comes_back_as_one(monkeypatch):
    handy = Handy(monkeypatch)
    assert voice.transcribe(LOUD * int(150 / 0.03)) == 'part1 part2 part3'
    assert max(handy.clips) <= 60 and sum(handy.clips) == pytest.approx(150)


def test_a_line_just_over_a_minute_is_cut():
    assert len(list(voice.pieces(LOUD * int(62 / 0.03)))) == 2


def test_a_short_line_is_one_clip(monkeypatch):
    handy = Handy(monkeypatch)
    assert voice.transcribe(LOUD * 100) == 'part1'
    assert len(handy.clips) == 1


def test_a_piece_ends_in_the_quiet_and_no_audio_goes_missing():
    frames = [LOUD] * voice.PIECE_FRAMES * 2
    frames[voice.PIECE_FRAMES - 60] = QUIET
    first, *rest = voice.pieces(b''.join(frames))
    assert len(first) == (voice.PIECE_FRAMES - 60) * voice.FRAME_BYTES
    assert first + b''.join(rest) == b''.join(frames)


def test_handy_failing_for_a_moment_costs_nothing(monkeypatch):
    handy = Handy(monkeypatch, failures=2)
    assert voice.transcribe(LOUD) == 'part3'
    assert len(handy.clips) == 3


def test_handy_that_keeps_failing_is_reported(monkeypatch):
    Handy(monkeypatch, failures=voice.TRANSCRIBE_TRIES)
    with pytest.raises(subprocess.CalledProcessError):
        voice.transcribe(LOUD)


def test_only_one_handy_runs_at_a_time(monkeypatch):
    handy = Handy(monkeypatch)
    runs = [threading.Thread(target=voice.transcribe, args=(LOUD,)) for _ in range(4)]
    for run in runs:
        run.start()
    for run in runs:
        run.join()
    assert len(handy.clips) == 4 and handy.most == 1


def second_part(monkeypatch, heard, gap, first='Claude 2, here is the idea', agents=('klod2',), delivered=True):
    """Say a named line that closes at 1000, then a 60 s line starting gap seconds later."""
    line = Line(monkeypatch, first, set(agents), delivered)
    voice.handle(b'', closed=1000.0)
    monkeypatch.setattr(voice, 'transcribe', lambda _: heard)
    line.sent.clear()
    voice.handle(MINUTE, closed=1000.0 + gap + 60)
    return line


def test_past_the_cap_the_line_goes_on_to_the_same_agent(monkeypatch):
    line = second_part(monkeypatch, 'and this is the second minute of it', 0)
    assert [agent for agent, _ in line.sent] == ['klod2']
    assert 'and this is the second minute of it' in line.sent[0][1]


@pytest.mark.parametrize(('gap', 'carried'), [(9.9, True), (10.1, False)])
def test_a_pause_to_think_keeps_the_line_with_its_agent(monkeypatch, gap, carried):
    line = second_part(monkeypatch, 'and then the rest of the thought', gap)
    assert bool(line.sent) is carried


def test_a_thought_can_carry_on_more_than_once(monkeypatch):
    line = second_part(monkeypatch, 'a second part of the thought', 5)
    voice.handle(MINUTE, closed=1070.0 + 60)  # past the first line's window, inside the second's
    assert len(line.sent) == 2


def test_a_named_line_is_not_a_continuation(monkeypatch):
    line = second_part(monkeypatch, 'Codex, take this one instead', 1, agents=('klod2', 'codex'))
    assert [agent for agent, _ in line.sent] == ['codex']


@pytest.mark.parametrize('heard', [
    'yes go ahead',  # short enough to be for someone in the room, and an agent would obey it
    '',
    'Claude 1 to Piotr, the tests pass today',  # a reply caught by the mic
    'Voice mode to Peter. Something went wrong here.',
])
def test_only_a_real_thought_of_his_carries_on(monkeypatch, heard):
    assert second_part(monkeypatch, heard, 1).sent == []


@pytest.mark.parametrize('heard', ['Codex run the tests', 'Codecs run the tests', 'Clot 1 do the thing now',
                                   'Plod 2 this is a test', 'Gordon check this for me'])
def test_a_call_with_an_unheard_name_does_not_land_on_the_last_agent(monkeypatch, heard):
    monkeypatch.setattr(voice, 'roster', lambda: {'codex': 'codex', 'klod one': 'klod1', 'klod two': 'klod2',
                                                  'gordon': 'triage'})
    assert second_part(monkeypatch, heard, 1).sent == []


def test_a_thought_about_nobody_still_carries_on_with_that_roster(monkeypatch):
    monkeypatch.setattr(voice, 'roster', lambda: {'codex': 'codex', 'klod one': 'klod1', 'klod two': 'klod2',
                                                  'gordon': 'triage'})
    assert len(second_part(monkeypatch, 'because the tests fail on master', 1).sent) == 1


def test_the_toggle_ends_carrying_on(monkeypatch):
    Path(voice.NO_CONTINUE).touch()
    assert second_part(monkeypatch, 'and then the rest of the thought', 1).sent == []


def test_a_line_that_failed_is_nothing_to_carry_on_from(monkeypatch):
    assert second_part(monkeypatch, 'and then the rest of the thought', 1, delivered=False).sent == []


def test_a_kept_line_reads_back_as_it_was_heard():
    kept = voice.keep(LOUD)
    with voice.wave.open(kept, 'rb') as audio:
        assert audio.readframes(audio.getnframes()) == LOUD
        assert audio.getframerate() == voice.RATE


def test_a_line_that_reached_its_agent_leaves_nothing_behind(monkeypatch):
    Line(monkeypatch, 'Claude 2, run the tests', {'klod2'})
    voice.handle(LOUD, voice.keep(LOUD))
    assert lost_files() == []


@pytest.mark.parametrize(('heard', 'agents', 'delivered'), [
    ('Please remember this idea', {'klod2'}, True),  # names nobody
    ('Codex, fix the test', {'klod2'}, True),  # no such agent
    ('Claude 2, yes do it', {'klod2'}, False),  # the bus refused
])
def test_a_line_that_reached_nobody_keeps_its_audio_and_words(monkeypatch, heard, agents, delivered):
    Line(monkeypatch, heard, agents, delivered)
    kept = voice.keep(LOUD)
    voice.handle(LOUD, kept)
    assert lost_files() == ['.txt', '.wav']
    assert voice.recovered(kept) == heard


def test_a_line_that_reached_only_one_agent_is_kept_whole(monkeypatch):
    line = Line(monkeypatch, 'both calls', {'codex'})
    monkeypatch.setattr(voice, 'calls', lambda _: [('codex', 'one'), ('gone', 'two')])
    voice.handle(LOUD, voice.keep(LOUD))
    assert len(line.sent) == 1
    assert lost_files() == ['.txt', '.wav']


def test_a_clip_with_no_words_keeps_its_audio(monkeypatch):
    Line(monkeypatch, '', {'klod2'})
    voice.handle(LOUD, voice.keep(LOUD))
    assert lost_files() == ['.wav']


def test_a_crash_before_the_words_keeps_the_audio(monkeypatch):
    def broken(_):
        raise subprocess.TimeoutExpired('handy', 120)

    monkeypatch.setattr(voice, 'transcribe', broken)
    kept = voice.keep(LOUD)
    with pytest.raises(subprocess.TimeoutExpired):
        voice.handle(LOUD, kept)
    assert lost_files() == ['.wav']


def test_the_stop_word_is_not_a_lost_line(monkeypatch):
    Line(monkeypatch, 'Stop stop.', {'klod2'})
    voice.handle(LOUD, voice.keep(LOUD))
    assert lost_files() == []


def test_the_toggle_ends_keeping_lines():
    Path(voice.NO_KEEP).touch()
    assert voice.keep(LOUD) is None
    assert lost_files() == []


def test_keeping_a_line_cannot_stop_the_capture_loop(monkeypatch, tmp_path):
    (tmp_path / 'a-file').touch()
    monkeypatch.setattr(voice, 'LOST_DIR', str(tmp_path / 'a-file' / 'lost'))
    assert voice.keep(LOUD) is None


def test_only_the_last_lines_are_kept(monkeypatch):
    monkeypatch.setattr(voice, 'LOST_KEPT', 2)
    Line(monkeypatch, 'Please remember this idea', set())
    kept = [voice.keep(LOUD) for _ in range(2)]
    voice.handle(LOUD, kept[0])
    voice.keep(LOUD)
    assert not os.path.exists(kept[0]) and not os.path.exists(f'{kept[0]}.txt')
    assert lost_files() == ['.wav', '.wav']


def open_line(frames):
    segmenter = voice.Segmenter()
    feed(segmenter, frames)
    return segmenter


def test_a_line_still_open_at_a_stop_is_kept():
    voice.rescue(open_line([LOUD] * (voice.MIN_VOICED + voice.START_FRAMES)))
    assert lost_files() == ['.wav']


@pytest.mark.parametrize('frames', [[], [QUIET] * 5, [LOUD] * (voice.MIN_VOICED - 2)])
def test_silence_or_a_click_at_a_stop_is_not_kept(frames):
    voice.rescue(open_line(frames))
    assert lost_files() == []


def test_stopping_the_relay_mid_line_keeps_what_was_said(tmp_path):
    bin_dir = tmp_path / 'bin'
    bin_dir.mkdir()
    started = tmp_path / 'started'
    parec = bin_dir / 'parec'
    parec.write_text(f'''#!{sys.executable}
import pathlib, sys, time
sys.stdout.buffer.write({QUIET!r} + {LOUD!r} * 120)  # past the pipe buffer, so the relay has read it
sys.stdout.buffer.flush()
pathlib.Path({str(started)!r}).write_text(' '.join(sys.argv))
time.sleep(5)
''')
    pkill = bin_dir / 'pkill'
    pkill.write_text('#!/bin/sh\nexit 0\n')
    parec.chmod(0o755)
    pkill.chmod(0o755)
    env = {'PATH': f'{bin_dir}:/usr/bin:/bin', 'HOME': str(tmp_path), 'XDG_RUNTIME_DIR': str(tmp_path)}
    relay = subprocess.Popen([sys.executable, str(ROOT / 'scripts' / '__voice_mode.py')], env=env,
                             stderr=subprocess.DEVNULL)
    deadline = time.monotonic() + 5
    while not started.exists() and time.monotonic() < deadline:
        time.sleep(0.01)
    time.sleep(0.2)
    relay.terminate()
    assert relay.wait(5) == 0  # a stop, so systemd does not call it a failure
    assert '--device' not in started.read_text()  # the mic is the system's default, not a name of ours
    assert len(list((tmp_path / 'voice-mode-lost').glob('*.wav'))) == 1


def test_lost_prints_the_words_of_a_kept_line(monkeypatch, capsys):
    Line(monkeypatch, 'Please remember this idea', set())
    voice.handle(LOUD, voice.keep(LOUD))
    capsys.readouterr()
    voice.lost()
    assert capsys.readouterr().out.split(' ', 1)[1] == 'Please remember this idea\n'


def test_lost_transcribes_a_line_that_never_got_that_far(monkeypatch, capsys):
    kept = voice.keep(LOUD)
    monkeypatch.setattr(voice, 'transcribe', lambda pcm: f'{len(pcm)} bytes of words')
    voice.lost()
    assert capsys.readouterr().out.split(' ', 1)[1] == f'{len(LOUD)} bytes of words\n'
    assert voice.recovered(kept) == f'{len(LOUD)} bytes of words'


def test_lost_points_at_audio_it_cannot_turn_into_words(monkeypatch):
    kept = voice.keep(LOUD)
    monkeypatch.setattr(voice, 'transcribe', lambda _: '')
    assert voice.recovered(kept) == f'(no words heard, audio in {kept})'

    def broken(_):
        raise subprocess.SubprocessError

    monkeypatch.setattr(voice, 'transcribe', broken)
    assert voice.recovered(kept) == f'(not transcribed, audio in {kept})'


def test_lost_says_so_when_there_is_nothing(capsys):
    voice.lost()
    assert capsys.readouterr().out == 'voice-mode: no lost lines\n'


class EndOfTest(BaseException):
    pass


def test_a_worker_outlives_a_bug(monkeypatch):
    monkeypatch.setattr(voice, 'LINE_STATUS', os.devnull)
    seen = []
    clips = voice.queue.Queue()
    clips.put('first')
    clips.put('second')

    def act(clip):
        seen.append(clip)
        raise (TypeError if clip == 'first' else EndOfTest)

    with pytest.raises(EndOfTest):
        voice.worker(clips, act)
    assert seen == ['first', 'second']


def test_a_light_that_cannot_change_costs_nothing(monkeypatch, tmp_path):
    monkeypatch.setattr(voice, 'LINE_STATUS', str(tmp_path))  # a folder, so open() fails
    voice.signal('sent')


def test_a_notice_that_cannot_play_costs_no_later_call(monkeypatch):
    line = Line(monkeypatch, 'three calls', {'codex', 'klod1'})

    def broken(_):
        raise subprocess.TimeoutExpired('piper', 30)

    monkeypatch.setattr(voice, 'say', broken)
    monkeypatch.setattr(voice, 'calls', lambda _: [('codex', 'one'), ('gone', 'two'), ('klod1', 'three')])
    voice.handle(LOUD, voice.keep(LOUD))
    assert [agent for agent, _ in line.sent] == ['codex', 'klod1']
    assert lost_files() == ['.txt', '.wav']
