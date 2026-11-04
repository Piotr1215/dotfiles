#!/usr/bin/env python3
"""Voice mode: hear Piotr on the default mic and pass named lines to agents over the bus.

Speech becomes text locally and the agents bus does the routing. A line that opens
with an agent's name ("Claude 2, run the tests") goes out as a DM to that name, so
any agent registered on the bus can be addressed, Claude or Codex. All other speech
is dropped. Run by voice-mode.service, switched from the toggle board.

A line that opens "check check" needs no exact name, because Parakeet has never heard
most of them. The next few words go to the quick decision model with the live roster,
and the line goes to the name they sound most like. Nothing else leaves the machine.
One breath can call several agents: each "check check" starts a call of its own.

A call opens a channel: every line after it goes to that agent, with no time limit,
until another call swaps it or the stop word closes it. It survives a relay restart
and ends at reboot. A flag file switches that off. The key phrase wins wherever it
falls in a line, and the words before it stay on the channel. "check once" sends a
single line to an agent and leaves the channel where it is, for an aside.

Every closed line waits in a RAM folder until all its calls are sent, so a crash, a
restart or a line that reached nobody costs no words. `__voice_mode.py --lost` prints
what is there. That includes room talk, so it holds few lines, and a flag file switches
it off. The journal still gets no words.

A faint sound on the default output tells Piotr what became of a line without looking.
One high note: the bus took it for a live agent, which does not prove the agent read it.
Two falling notes: an error. A called agent was not reached or no agent fit, the relay
hit a fault, or it stopped with a line in hand. Room talk and noise play nothing, so no
sound means the line did not go: say it again.

Lines travel as messages, never as keys, so speech cannot answer a permission prompt.
They are not marked [HUMAN], because a transcript can be misheard.

Agents speak one at a time, in a queue. Saying "stop stop" on its own ends the reply
playing, the next one takes over, and the channel closes, so the next line needs a
name. The agents keep working.

When Piotr starts to talk, whoever is speaking stops for good, because he has heard
enough. A voice model decides that, so a thud or a breath leaves speech alone, though
any voice counts, not only his. A voice pauses the reply, and it ends once Handy hears
words in the line, because a throat clear reads as voice. No words and it carries on.
Only the reply playing ends: the next one keeps its turn. A line that reaches an agent also ends that agent's queued replies and any it
is still making, because he has moved on, and other agents keep theirs. One flag file
brings back pausing and carrying on from the same spot, another switches all of this off.

Mic and speech follow the system's default devices, the ones GNOME's Sound panel sets.
Handy with no device selected reads the same ones, and must stay that way: a selected
mic is opened raw, which fails while this stream holds it, and Handy then erases it.
"""
import array
import collections
import glob
import json
import math
import os
import queue
import re
import signal as signals
import subprocess
import sys
import tempfile
import threading
import time
import wave

# With no target the default output plays it; the name is how pkill finds this speech.
PLAYER = 'pw-play -P media.name=klod-voice'
HANDY = os.path.expanduser('~/.local/bin/handy')
PIPER = os.path.join(os.path.dirname(os.path.abspath(__file__)), '__piper_quiet.py')
VOICE = os.path.expanduser('~/.local/share/piper-voices/lessac-medium/en_US-lessac-medium.onnx')
VOICE_LOCK = os.path.expanduser('~/.local/state/klod-voice.lock')
NO_BARGE_IN = os.path.expanduser('~/.local/state/klod-voice/no-barge-in')
RESUME_SPEECH = os.path.expanduser('~/.local/state/klod-voice/resume-speech')
SPEECH_CUT = os.path.expanduser('~/.local/state/klod-voice/cut')  # the reply hook drops what it was making
NO_KEEP = os.path.expanduser('~/.local/state/klod-voice/no-keep')
NO_LISTENING = os.path.expanduser('~/.local/state/klod-voice/no-listening')
NO_CONTINUE = os.path.expanduser('~/.local/state/klod-voice/no-continue')
NATS = os.path.expanduser('~/.local/bin/nats')
SND = os.path.expanduser('~/dev/agents-mcp-server/build/snd.js')
NATS_URL = os.environ.get('AGENTS_NATS_URL', 'nats://nats-nats-tailscale.tail165ec.ts.net:4222')
# What became of the last line, for the top bar to blink: sent means the bus took it,
# which proves it was published, not read; dropped means it reached nobody, including
# a voiced clip that came back with no words; failed means it named an agent and
# could not be sent; armed means a line opened with the wake word and is still going.
# See .config/argos/notion-mic.1s.sh.
RUNTIME_DIR = os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')
LINE_STATUS = os.path.join(RUNTIME_DIR, 'voice-mode-line')
LOST_DIR = os.path.join(RUNTIME_DIR, 'voice-mode-lost')  # tmpfs: gone at reboot
LOST_KEPT = 20
SOUND_FILE = os.path.join(RUNTIME_DIR, 'voice-mode-sound')
SOUND_PEAK = 2500  # 12 dB under the average level of a Piper reply, measured on one
SOUND_NOTES = {'sent': (880,), 'miss': (440, 330)}
NOTE_SAMPLES = 2400  # 150 ms
CHANNEL = os.path.join(RUNTIME_DIR, 'voice-mode-channel')  # tmpfs: a restart keeps it, a reboot does not

RATE = 16000
FRAME_BYTES = 960  # 30 ms of s16le mono

# A headset gates silence to zero, with speech at 300 to 800 RMS. A laptop mic idles at
# thousands, so speech has to clear the room as well as this level.
SPEECH_RMS = 100
HIGH_PASS = 0.96  # one pole at about 100 Hz: 65% of the laptop mic's noise is under 50 Hz
NOISE_WINDOW = 170  # 5 s: speech has gaps, so the quietest frame in here is the room
NOISE_MARGIN = 3  # measured on 32 s of laptop mic noise: 3 opened no line, 2.5 opened two
START_FRAMES = 3  # 90 ms of speech opens an utterance
END_FRAMES = 84  # 2.5 s of quiet closes it; Piotr pauses to think mid-line
MIN_VOICED = 10  # shorter than 300 ms of speech is a click or a cough
PRE_ROLL = 15  # 450 ms kept up to the onset, so first words survive
MAX_FRAMES = 20000  # 10 min, pauses included; past that the rest carries on to the same agent
PIECE_FRAMES = 2000  # 60 s at a time: Handy ran out of GPU memory on 6 min of speech, not on 2.5
SEEK_FRAMES = 170  # 5 s back from a piece's end, to cut in a quiet spot and not in a word
TRANSCRIBE_TRIES = 3
QUICK_END = 20  # 0.6 s of quiet is enough to test a short burst for the stop word
QUICK_MAX = 100  # 3 s; anything longer is a line, not the stop word
OPENING_FRAMES = 67  # 2 s with the lead-in: at 1.5 s Handy missed the wake word in one of three Piper voices
HOLD_FRAMES = 16  # about 0.5 s: how soon a reply that starts mid-line is paused
SILERO = os.path.expanduser('~/.local/share/silero-vad/silero_vad_v4.onnx')  # copied from Handy
SILERO_CHUNK = 1024  # 32 ms of s16le mono, the length the model reads
SILERO_FLOOR = 0.5
SILERO_RUN = 12  # 384 ms in a row. On 33 real clips: 6 of 6 lines by 2.3 s, 0 of 27 noises

BUS_NAME = 'human-via-voice'
VOICE_TAG = '[PIOTR VIA VOICE]'
VOICE_NOTE = ('(Local transcript, can be misheard. Answer in your chat. '
              'Confirm anything destructive with him first.)')
PEER_TTL_SECONDS = 30  # agents-mcp-server's own: three missed beats and a peer is gone
SND_TIMEOUT_SECONDS = 15

QUICK_DECIDE = os.path.expanduser('~/.claude/scripts/__quick_decide.py')
FIT_QUESTION = ('Speech recognition misheard an agent name at the start of this text. Read the text and each '
                'choice aloud and pick the choice that sounds closest. A word that sounds like a number counts '
                'as that number: to and too are two, won is one, ate is eight.')
FIT_WORDS = 8  # room for a spoken issue id; the rest of the line stays here
FIT_FLOOR = 0.6  # measured: named lines came back at 0.70 or more, absent names mostly under 0.55
FIT_TIMEOUT_SECONDS = 10

# Parakeet hears "klod" as cloud or plot, and Piotr's "Claude 2" as "Claude too".
# Cloud and plot are everyday words, so they need a real number; "cloud to edge"
# is not an address. Other names need a pause after them, so "Gordon is out" is talk.
ADDRESS = re.compile(
    r'^\W*(?:stop\W+stop\W+)?(?:hey\W+)?(?:(?:claude|klod|clod)\W*(\d|one|won|two|to|too)\b'
    r'|(?:cloud|plot)\W*(\d|one|two)\b|(codex|gordon|kendra)\s*[,.:;!?])\W*(.*)$',
    re.IGNORECASE | re.DOTALL,
)
BUS_NAMES = {'gordon': 'triage', 'kendra': 'intake'}
SPOKEN_NAMES = {bus: name for name, bus in BUS_NAMES.items()}
SPOKEN_DIGITS = {'one': '1', 'won': '1', 'two': '2', 'to': '2', 'too': '2'}
DIGIT_WORDS = 'zero one two three four five six seven eight nine'.split()
WAKE = re.compile(r'\bcheck\W+(check|once)\b\W*', re.IGNORECASE)
STOP_WORD = re.compile(r'\W*stop\W+stop\W*', re.IGNORECASE)
# Every spoken reply opens "klod1 to Piotr:", so one that reached the mic must not
# route back to the agent that said it.
OWN_SPEECH = re.compile(r'to\W+(?:piotr|peter)\b', re.IGNORECASE)


Call = collections.namedtuple('Call', 'agent message once', defaults=(False,))  # once: leave the channel


def route(text):
    """Return (agent, message) when the line opens with an agent's name."""
    match = ADDRESS.match(text.strip())
    if not match or not match[4] or OWN_SPEECH.match(match[4]):
        return None
    if match[3]:
        name = match[3].lower()
        return BUS_NAMES.get(name, name), match[4]
    number = (match[1] or match[2]).lower()
    return f'klod{SPOKEN_DIGITS.get(number, number)}', match[4]


def spoken(agent):
    """An agent's name as it is said aloud: klod2 is klod two, triage is gordon."""
    name = SPOKEN_NAMES.get(agent, agent).replace('-', ' ')
    return ' '.join(re.sub(r'\d', lambda digit: f' {DIGIT_WORDS[int(digit[0])]} ', name).split())


def rms(frame):
    samples = array.array('h', frame)
    return math.sqrt(sum(s * s for s in samples) / len(samples))


class Segmenter:
    """Cut a stream of frames into utterances."""

    def __init__(self):
        self.lead_in = collections.deque(maxlen=PRE_ROLL)
        self.utterance = None
        self.onset = self.voiced = self.quiet = 0
        self.levels = collections.deque(maxlen=NOISE_WINDOW)
        self.last_in = self.last_out = 0.0

    def level(self, frame):
        """The frame's RMS with the rumble below speech filtered out."""
        energy = 0.0
        samples = array.array('h', frame)
        for sample in samples:
            self.last_out = HIGH_PASS * (self.last_out + sample - self.last_in)
            self.last_in = sample
            energy += self.last_out * self.last_out
        return math.sqrt(energy / len(samples))

    def push(self, frame):
        """Take one frame. Return the utterance's PCM when one has just closed."""
        level = self.level(frame)
        self.levels.append(level)
        loud = level >= max(SPEECH_RMS, NOISE_MARGIN * min(self.levels))
        if self.utterance is None:
            self.lead_in.append(frame)
            self.onset = self.onset + 1 if loud else 0
            if self.onset >= START_FRAMES:
                self.utterance = list(self.lead_in)
                self.lead_in.clear()
                self.voiced, self.quiet = self.onset, 0
            return None
        self.utterance.append(frame)
        self.voiced += loud
        self.quiet = 0 if loud else self.quiet + 1
        if self.quiet < END_FRAMES and len(self.utterance) < MAX_FRAMES:
            return None
        utterance, self.utterance, self.onset = self.utterance, None, 0
        return b''.join(utterance) if self.voiced >= MIN_VOICED else None

    def opening(self):
        """Return the open utterance once, when it is long enough to hold the wake word."""
        if self.utterance is None or len(self.utterance) != OPENING_FRAMES or self.voiced < MIN_VOICED:
            return None
        return b''.join(self.utterance)

    def burst(self):
        """Return the open utterance at the moment a short one goes quiet."""
        if self.utterance is None or self.quiet != QUICK_END:
            return None
        short = len(self.utterance) <= QUICK_MAX and self.voiced >= MIN_VOICED
        return b''.join(self.utterance) if short else None


class Presence:
    """Who the bus has heard from lately, from its presence beats."""

    def __init__(self):
        self.last_beat = {}

    def beat(self, line):
        try:
            self.last_beat[json.loads(line)['name']] = time.monotonic()
        except (ValueError, KeyError, TypeError):
            pass

    def has(self, name):
        last = self.last_beat.get(name)
        return last is not None and time.monotonic() - last < PEER_TTL_SECONDS

    def live(self):
        return [name for name in list(self.last_beat) if self.has(name)]


PRESENCE = Presence()
HANDY_TURN = threading.Lock()  # measured: of three Handys at once, one ran out of GPU memory


def registered(name):
    """True while name is on the bus. snd does not check, and a DM to nobody is lost."""
    return PRESENCE.has(name)


def roster():
    """Spoken name to bus name for everyone who can be called. Gordon and Kendra stay
    on it while they are away, so calling one gets the notice, not the nearest agent."""
    names = {*PRESENCE.live(), *BUS_NAMES.values()}
    return {spoken(name): name for name in sorted(names) if not name.startswith('human-via-')}


def closest(heard):
    """Return the agent whose name the line's opening sounds most like, if one sounds close."""
    names = roster()
    # On stdin, not argv: argv reaches error messages, and the relay logs no words.
    decided = subprocess.run([QUICK_DECIDE, '-j', '-c', ','.join(names), FIT_QUESTION],
                             input=' '.join(heard.split()[:FIT_WORDS]), capture_output=True,
                             text=True, timeout=FIT_TIMEOUT_SECONDS, check=True)
    answer = json.loads(decided.stdout)['answers']['q']
    return names[answer['choice']] if answer['probabilities'][answer['choice']] >= FIT_FLOOR else None


def deliver(agent, text):
    """DM text to the agent over the bus. False when the publish fails."""
    env = {**os.environ, 'SND_FROM': BUS_NAME, 'AGENTS_NATS_URL': NATS_URL}
    try:
        return subprocess.run(['node', SND, agent, text], env=env, capture_output=True,
                              timeout=SND_TIMEOUT_SECONDS).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def mark_cut(path):
    """Tell the reply hook to drop what it is still making."""
    try:
        with open(path, 'a', encoding='utf-8'):
            os.utime(path)
    except OSError as err:  # called from the capture loop, which must keep running
        print(f'voice-mode: cut not marked: {type(err).__name__}', file=sys.stderr, flush=True)


def silence():
    """End the reply playing now. The next one in the queue takes over."""
    subprocess.run(['pkill', '-f', f'^(timeout .*)?{PLAYER}'], check=False)
    hold_speech(False)  # paused speech takes the signal only once it wakes


def silence_agent(agent):
    """End one agent's speech, queued replies and replies being made. Others keep their turn."""
    tags = sorted({agent, SPOKEN_NAMES.get(agent, agent)})  # Gordon's pane may carry either name
    for tag in tags:
        mark_cut(f'{SPEECH_CUT}.{tag}')
    names = '|'.join(re.escape(tag) for tag in tags)
    subprocess.run(['pkill', '-f', rf'^(flock .*|timeout .*)?{PLAYER} .*\.({names})\.wav'], check=False)
    hold_speech(False)


def hold_speech(held):
    """Pause the speech playing now, or let it carry on. Its lock keeps the rest queued."""
    subprocess.run(['pkill', '-STOP' if held else '-CONT', '-f', f'^{PLAYER}'], check=False)


class Silero:
    """Handy's voice model: how likely each 32 ms chunk of a line is speech."""

    def __init__(self):
        import numpy  # pylint: disable=import-outside-toplevel
        import onnxruntime  # pylint: disable=import-outside-toplevel
        options = onnxruntime.SessionOptions()
        options.intra_op_num_threads = options.inter_op_num_threads = 1
        self.numpy = numpy
        self.session = onnxruntime.InferenceSession(SILERO, options, providers=['CPUExecutionProvider'])
        self.reset()

    def reset(self):
        self.memory = [self.numpy.zeros((2, 1, 64), dtype=self.numpy.float32) for _ in 'hc']

    def score(self, chunk):
        samples = self.numpy.frombuffer(chunk, dtype=self.numpy.int16).astype(self.numpy.float32) / 32768
        chance, *self.memory = self.session.run(None, {
            'input': samples[None], 'sr': self.numpy.array(RATE, dtype=self.numpy.int64),
            'h': self.memory[0], 'c': self.memory[1]})
        return float(chance[0][0])


def voice_model():
    """The model, or None: speech then plays through everything but the stop word."""
    try:
        return Silero()
    except Exception as err:  # pylint: disable=broad-except  # no model must not cost the mic
        print(f'voice-mode: no voice check: {type(err).__name__}', file=sys.stderr, flush=True)
        return None


class VoiceCheck:
    """Say when the open line holds a voice. The level gate cannot: it opens on noise too."""

    def __init__(self, model):
        self.model = model
        self.pending, self.run, self.heard = b'', 0, False

    def hear(self, frame, line_open):
        if not self.model:
            return False
        if not line_open:
            if self.pending or self.run or self.heard:
                self.model.reset()
                self.pending, self.run, self.heard = b'', 0, False
            return False
        if self.heard:
            return True
        self.pending += frame
        while len(self.pending) >= SILERO_CHUNK and not self.heard:
            chunk, self.pending = self.pending[:SILERO_CHUNK], self.pending[SILERO_CHUNK:]
            self.run = self.run + 1 if self.model.score(chunk) >= SILERO_FLOOR else 0
            self.heard = self.run >= SILERO_RUN
        return self.heard


class BargeIn:
    """Pause speech on a voice, and end it once the line holds words.

    A throat clear passes the voice check, so only words end a reply. Set by check_wake,
    off the capture loop. The resume setting keeps every line a pause.
    """

    def __init__(self):
        self.frames = 0
        self.cut = False
        self.words = False

    def update(self, talking, line_open=True):
        if talking and not os.path.exists(NO_BARGE_IN):
            if self.frames % HOLD_FRAMES == 0:
                hold_speech(True)
            self.frames += 1
            if self.words and not self.cut and not os.path.exists(RESUME_SPEECH):
                silence()
                self.cut = True
        elif self.frames:
            hold_speech(False)
            self.frames, self.cut = 0, False
        if not line_open:
            self.words = False


def say(text):
    with tempfile.NamedTemporaryFile(suffix='.wav') as speech:
        subprocess.run([PIPER, '-m', VOICE, '-f', speech.name], input=text, text=True,
                       capture_output=True, timeout=30, check=True)
        subprocess.run(['flock', VOICE_LOCK, 'timeout', '30', *PLAYER.split(), speech.name],
                       timeout=90, check=True)


def sound(name):
    """Play what became of a line. Its own stream, so no pause or cut touches it, and no lock waits."""
    path = f'{SOUND_FILE}-{name}.wav'
    try:
        if not os.path.exists(path):
            write_wav(path, array.array('h', (
                round(SOUND_PEAK * (1 - abs(2 * n / NOTE_SAMPLES - 1)) * math.sin(2 * math.pi * hz * n / RATE))
                for hz in SOUND_NOTES[name] for n in range(NOTE_SAMPLES))).tobytes())
        subprocess.run(['pw-play', '-P', 'media.name=klod-sound', path], timeout=5, check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError) as err:  # the line's fate is already settled
        print(f'voice-mode: no sound: {type(err).__name__}', file=sys.stderr, flush=True)


def write_wav(path, pcm):
    with wave.open(path, 'wb') as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(pcm)


def pieces(pcm):
    """Cut a long line for Handy at its quietest moments. Short lines come back whole."""
    while len(pcm) > PIECE_FRAMES * FRAME_BYTES:
        frames = range((PIECE_FRAMES - SEEK_FRAMES) * FRAME_BYTES, PIECE_FRAMES * FRAME_BYTES, FRAME_BYTES)
        cut = min(frames, key=lambda start: rms(pcm[start:start + FRAME_BYTES]))
        yield pcm[:cut]
        pcm = pcm[cut:]
    yield pcm


def transcribe_piece(pcm):
    """One clip through Handy, waiting out a GPU that something else has filled."""
    with tempfile.NamedTemporaryFile(suffix='.wav') as audio:
        write_wav(audio.name, pcm)
        for tries_left in reversed(range(TRANSCRIBE_TRIES)):
            try:
                with HANDY_TURN:
                    result = subprocess.run([HANDY, '--transcribe-file', audio.name, '--json'],
                                            capture_output=True, text=True, timeout=30, check=True)
                return json.loads(result.stdout)['text']
            except subprocess.CalledProcessError:
                if not tries_left:
                    raise
                time.sleep(1)


def transcribe(pcm):
    return ' '.join(filter(None, (transcribe_piece(piece) for piece in pieces(pcm))))


def signal(status):
    try:
        with open(LINE_STATUS, 'w', encoding='utf-8') as marker:
            marker.write(status)
    except OSError as err:  # a light that cannot change must not cost the line
        print(f'voice-mode: {type(err).__name__}', file=sys.stderr, flush=True)


def keep(pcm):
    """Write a closed line down before anything can lose it, and return where."""
    if os.path.exists(NO_KEEP):
        return None
    try:
        os.makedirs(LOST_DIR, mode=0o700, exist_ok=True)
        path = os.path.join(LOST_DIR, f'{time.time_ns()}.wav')
        write_wav(path, pcm)
        for old in sorted(glob.glob(os.path.join(LOST_DIR, '*.wav')))[:-LOST_KEPT]:
            forget(old)
    except OSError as err:  # called from the capture loop, which must keep running
        print(f'voice-mode: line not kept: {type(err).__name__}', file=sys.stderr, flush=True)
        return None
    return path


def forget(kept):
    """Remove a kept line and its words, once nothing can still need them."""
    for path in (kept, f'{kept}.txt') if kept else ():
        if os.path.exists(path):
            os.remove(path)


def note(kept, text):
    """Put the words beside the audio of a line that did not reach everyone."""
    if kept and text:
        with open(f'{kept}.txt', 'w', encoding='utf-8') as words:
            words.write(text)


def rescue(segmenter, utterances):
    """Keep the line still open when the relay stops, and say so if any line is going nowhere."""
    cut_off = segmenter.utterance and segmenter.voiced >= MIN_VOICED
    if cut_off:
        keep(b''.join(segmenter.utterance))
    if cut_off or utterances.unfinished_tasks:
        sound('miss')


def recovered(path):
    """A kept line's words, from its audio when it never got as far as words."""
    if os.path.exists(f'{path}.txt'):
        with open(f'{path}.txt', encoding='utf-8') as words:
            return words.read()
    try:
        with wave.open(path, 'rb') as audio:
            return transcribe(audio.readframes(audio.getnframes())) or f'(no words heard, audio in {path})'
    except (OSError, EOFError, wave.Error, subprocess.SubprocessError, ValueError, KeyError):
        return f'(not transcribed, audio in {path})'


def lost():
    """Print the lines that reached nobody, oldest first."""
    kept = sorted(glob.glob(os.path.join(LOST_DIR, '*.wav')))
    for path in kept:
        said = time.localtime(int(os.path.basename(path).removesuffix('.wav')) / 1e9)
        print(f'{time.strftime("%H:%M:%S", said)} {recovered(path)}')
    if not kept:
        print('voice-mode: no lost lines')


def calls(text):
    """Return a Call for each call in a line. A weak name leaves agent as None.

    A key phrase starts a call wherever it falls, unless what follows names nobody: the
    phrase in a sentence and a misheard name look alike, so the words stay in the call
    before it and a None entry still turns the light orange. Words ahead of the first
    call stay on the open channel, or go with that call when none is open. All names
    are settled before anything is sent, so a failed decision sends nothing.
    """
    opening, *called = WAKE.split(text.strip())
    named = route(opening)
    lead = ''
    if not named and re.search(r'\w', opening) and not STOP_WORD.fullmatch(opening):
        if not called:
            return []
        lead = opening.strip(' ,;:')
    lines, unplaced = ([Call(*named)] if named else []), []
    for kind, part in zip(called[::2], (part.strip(' ,;:') for part in called[1::2])):
        if not re.search(r'\w', part):
            continue
        agent = closest(part)
        if agent or not (lines or lead):
            lines.append(Call(agent, part, kind.lower() == 'once'))
        elif lines:
            lines[-1] = lines[-1]._replace(message=f'{lines[-1].message} check {kind} {part}')
            unplaced.append(Call(None, part))
        else:
            lead = f'{lead} check {kind} {part}'
    if lead and not lines:
        return []
    if lead and not (ahead := continued(lead)):
        lines[0] = lines[0]._replace(message=f'{lead} {lines[0].message}')
    return (ahead if lead else []) + lines + unplaced


def refuse(notice):
    """Show a call failed at once. The words wait their turn behind any reply playing."""
    signal('failed')
    sound('miss')
    say(notice)
    return 'failed'


def send(agent, message):
    """Pass one call to its agent and return what became of it."""
    if not agent:
        print('voice-mode: line names no agent, dropped', flush=True)
        return 'dropped'
    if not registered(agent):
        return refuse(f'Voice mode to Piotr. No agent is registered as {agent}.')
    if deliver(agent, f'{VOICE_TAG} Piotr to {agent}: {message} {VOICE_NOTE}'):
        print(f'voice-mode: line sent to {agent}', flush=True)
        return 'sent'
    return refuse(f'Voice mode to Piotr. {agent} did not get that line.')


def attempt(agent, message):
    """Send one call. A notice that cannot play must not cost the calls after it."""
    try:
        return send(agent, message)
    except (OSError, subprocess.SubprocessError) as err:
        print(f'voice-mode: {type(err).__name__}', file=sys.stderr, flush=True)
        return 'failed'


def channel():
    """The agent on the open channel, or nothing. On disk, because a relay restart must not close it."""
    try:
        with open(CHANNEL, encoding='utf-8') as agent:
            return agent.read()
    except OSError:
        return None


def open_channel(agent):
    try:
        with open(CHANNEL, 'w', encoding='utf-8') as marker:
            marker.write(agent)
    except OSError as err:  # the line is already sent, and must not read as failed
        print(f'voice-mode: channel not kept: {type(err).__name__}', file=sys.stderr, flush=True)


def close_channel():
    try:
        os.remove(CHANNEL)
    except OSError:  # already closed: a short stop word reaches here on two paths
        pass


def continued(text):
    """Return the call for a nameless line: it stays on the open channel.

    Only another call or the stop word moves the channel, so a line that merely sounds
    like a name stays on it. Speech the mic caught from a reply never does.
    """
    words = text.split()
    agent = channel()
    if not agent or not words or os.path.exists(NO_CONTINUE) or OWN_SPEECH.search(' '.join(words[:6])):
        return []
    return [Call(agent, text)]


def moved_on(agent):
    """A line reached this agent, so whatever it still had to say is out of date."""
    if not os.path.exists(NO_BARGE_IN) and not os.path.exists(RESUME_SPEECH):
        silence_agent(agent)


def handle(pcm, kept=None):
    """Send one utterance to each agent it calls, show the worst outcome, free its audio if sent."""
    text = transcribe(pcm)
    if STOP_WORD.fullmatch(text):  # check_stop acted on a short one, moments earlier
        close_channel()
        forget(kept)
        return
    found = calls(text) or continued(text) or [Call(None, '')]
    outcomes = [attempt(call.agent, call.message) for call in found]
    for call, outcome in zip(found, outcomes):
        if outcome == 'sent':
            moved_on(call.agent)
            if not call.once:
                open_channel(call.agent)
    status = next(status for status in ('failed', 'dropped', 'sent') if status in outcomes)
    signal(status)
    if status == 'sent':
        forget(kept)
        sound('sent')
        return
    note(kept, text)
    if status == 'dropped' and WAKE.search(text):  # he called and no agent fit. A failed call played it already
        sound('miss')


def check_wake(pcm, segmenter, barge_in):
    """Read a line's opening while Piotr still talks: words end speech, the key phrase lights the bar.

    The line's outcome replaces the light, so a line that closed first leaves it alone.
    A failure here costs no words, the whole line is transcribed when it closes, so it
    stays off the light instead of reaching worker's red.
    """
    try:
        heard = transcribe(pcm)
    except (OSError, subprocess.SubprocessError, ValueError, KeyError) as err:
        print(f'voice-mode: opening not checked: {type(err).__name__}', file=sys.stderr, flush=True)
        return
    if heard.strip() and segmenter.utterance is not None:
        barge_in.words = True
    if WAKE.match(heard.strip()) and segmenter.utterance is not None:
        signal('armed')


def check_stop(pcm, barge_in):
    """End the reply playing and close the channel when a short burst is the stop word.

    Saying the word may have ended that reply already, and a second cut would take the
    next one too, which Piotr still wants to hear.
    """
    if STOP_WORD.fullmatch(transcribe(pcm)):
        if not barge_in.cut:
            silence()
        close_channel()
        print('voice-mode: stop word heard', flush=True)


def worker(clips, act):
    """Transcribe off the capture loop, which must keep draining the mic."""
    while True:
        pcm = clips.get()
        try:
            act(pcm)
        except Exception as err:  # a dead worker would take every later line with it
            print(f'voice-mode: {type(err).__name__}: {err}', file=sys.stderr, flush=True)
            signal('failed')
            sound('miss')
        finally:
            clips.task_done()


def watch_presence(stopping):
    """Feed the bus's presence beats to PRESENCE. Without them no name resolves, so end the relay."""
    beats = subprocess.Popen([NATS, '--server', NATS_URL, 'sub', 'agents.presence', '--raw'],
                             stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    for line in beats.stdout:
        PRESENCE.beat(line)
    # systemd sends SIGTERM to the subscriber and relay together. Give the main
    # thread time to receive it before treating the subscriber's EOF as a crash.
    if stopping.wait(1):
        return
    if os.path.exists(NO_LISTENING):
        os.kill(os.getpid(), signals.SIGTERM)
        return
    print('voice-mode: presence stream ended', file=sys.stderr, flush=True)
    os._exit(1)


def main():
    stopping = threading.Event()
    def stop(*_):
        stopping.set()
        sys.exit(0)
    signals.signal(signals.SIGTERM, stop)
    threading.Thread(target=watch_presence, args=(stopping,), daemon=True).start()
    utterances = queue.Queue()
    bursts = queue.Queue()  # its own worker: a slow delivery must not hold up the stop word
    openings = queue.Queue()
    segmenter = Segmenter()
    barge_in = BargeIn()
    threading.Thread(target=worker, args=(utterances, lambda line: handle(*line)), daemon=True).start()
    threading.Thread(target=worker, args=(bursts, lambda pcm: check_stop(pcm, barge_in)), daemon=True).start()
    threading.Thread(target=worker, args=(openings, lambda pcm: check_wake(pcm, segmenter, barge_in)), daemon=True).start()
    mic = subprocess.Popen(['parec', f'--rate={RATE}', '--channels=1',
                            '--format=s16le', '--latency-msec=30'], stdout=subprocess.PIPE)
    voice_check = VoiceCheck(voice_model())
    hold_speech(False)  # a relay that died mid-line left speech paused
    try:
        while len(frame := mic.stdout.read(FRAME_BYTES)) == FRAME_BYTES:
            pcm = segmenter.push(frame)
            line_open = segmenter.utterance is not None
            barge_in.update(voice_check.hear(frame, line_open), line_open)
            if pcm:
                utterances.put((pcm, keep(pcm)))
            if burst := segmenter.burst():
                bursts.put(burst)
            if opening := segmenter.opening():
                openings.put(opening)
    finally:
        rescue(segmenter, utterances)
    if stopping.wait(1) or os.path.exists(NO_LISTENING):
        return
    sys.exit('voice-mode: microphone stream ended')


if __name__ == '__main__':
    lost() if sys.argv[1:] == ['--lost'] else main()
