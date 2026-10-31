#!/usr/bin/env python3
"""Voice mode: hear Piotr on the headset and pass named lines to agents over the bus.

Speech becomes text locally and the agents bus does the routing. A line that opens
with an agent's name ("Claude 2, run the tests") goes out as a DM to that name, so
any agent registered on the bus can be addressed, Claude or Codex. All other speech
is dropped. Run by voice-mode.service, switched from the toggle board.

A line that opens "check check" needs no exact name, because Parakeet has never heard
most of them. The next few words go to the quick decision model with the live roster,
and the line goes to the name they sound most like. Nothing else leaves the machine.
One breath can call several agents: each "check check" starts a call of its own.

Lines travel as messages, never as keys, so speech cannot answer a permission prompt.
They are not marked [HUMAN], because a transcript can be misheard.

Saying "stop stop" on its own cuts all speech and the replies queued behind it.
The agents keep working; only their voices stop.

While Piotr talks, whoever is speaking pauses and carries on from the same spot when
his line ends. A flag file switches that off, from the toggle board.

Handy must stay on the system default mic, with the headset as that default.
A selected mic is opened raw, which fails while this stream holds the device,
and Handy then erases the selection.
"""
import array
import collections
import json
import math
import os
import queue
import re
import subprocess
import sys
import tempfile
import threading
import time
import wave

SOURCE = 'alsa_input.usb-Logitech_PRO_X_Wireless_Gaming_Headset-00.mono-fallback'
SINK = 'alsa_output.usb-Logitech_PRO_X_Wireless_Gaming_Headset-00.analog-stereo'
HANDY = os.path.expanduser('~/.local/bin/handy')
PIPER = os.path.join(os.path.dirname(os.path.abspath(__file__)), '__piper_quiet.py')
VOICE = os.path.expanduser('~/.local/share/piper-voices/lessac-medium/en_US-lessac-medium.onnx')
VOICE_LOCK = os.path.expanduser('~/.local/state/klod-voice.lock')
NO_BARGE_IN = os.path.expanduser('~/.local/state/klod-voice/no-barge-in')
NATS = os.path.expanduser('~/.local/bin/nats')
SND = os.path.expanduser('~/dev/agents-mcp-server/build/snd.js')
NATS_URL = os.environ.get('AGENTS_NATS_URL', 'nats://nats-nats-tailscale.tail165ec.ts.net:4222')
# What became of the last line, for the top bar to blink: sent means the bus took it,
# which proves it was published, not read; dropped means it reached nobody, including
# a voiced clip that came back with no words; failed means it named an agent and
# could not be sent; armed means a line opened with the wake word and is still going.
# See .config/argos/notion-mic.1s.sh.
LINE_STATUS = os.path.join(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}'),
                           'voice-mode-line')

RATE = 16000
FRAME_BYTES = 960  # 30 ms of s16le mono

# The headset gates silence to zero; measured speech runs at 300 to 800 RMS.
SPEECH_RMS = 100
START_FRAMES = 3  # 90 ms of speech opens an utterance
END_FRAMES = 84  # 2.5 s of quiet closes it; Piotr pauses to think mid-line
MIN_VOICED = 10  # shorter than 300 ms of speech is a click or a cough
PRE_ROLL = 15  # 450 ms kept up to the onset, so first words survive
MAX_FRAMES = 2000  # 60 s, pauses included; audio past the cut has no name and is lost
QUICK_END = 20  # 0.6 s of quiet is enough to test a short burst for the stop word
QUICK_MAX = 100  # 3 s; anything longer is a line, not the stop word
OPENING_FRAMES = 67  # 2 s with the lead-in: at 1.5 s Handy missed the wake word in one of three Piper voices
HOLD_FRAMES = 16  # about 0.5 s: how soon a reply that starts mid-line is paused

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
WAKE = re.compile(r'\bcheck\W+check\b\W*', re.IGNORECASE)
STOP_WORD = re.compile(r'\W*stop\W+stop\W*', re.IGNORECASE)
# Every spoken reply opens "klod1 to Piotr:", so one that reached the mic must not
# route back to the agent that said it.
OWN_SPEECH = re.compile(r'to\W+(?:piotr|peter)\b', re.IGNORECASE)


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

    def push(self, frame):
        """Take one frame. Return the utterance's PCM when one has just closed."""
        loud = rms(frame) >= SPEECH_RMS
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
    except subprocess.TimeoutExpired:
        return False


def silence():
    """End the speech playing now and the replies queued behind it."""
    subprocess.run(['pkill', '-f', f'^(flock .*|timeout .*)?pw-play --target {SINK}'], check=False)
    hold_speech(False)  # paused speech takes the signal only once it wakes


def hold_speech(held):
    """Pause the speech playing now, or let it carry on. Its lock keeps the rest queued."""
    subprocess.run(['pkill', '-STOP' if held else '-CONT', '-f', f'^pw-play --target {SINK}'], check=False)


class BargeIn:
    """Keep speech paused for as long as Piotr is talking."""

    def __init__(self):
        self.frames = 0

    def update(self, talking):
        if talking and not os.path.exists(NO_BARGE_IN):
            if self.frames % HOLD_FRAMES == 0:
                hold_speech(True)
            self.frames += 1
        elif self.frames:
            hold_speech(False)
            self.frames = 0


def say(text):
    with tempfile.NamedTemporaryFile(suffix='.wav') as speech:
        subprocess.run([PIPER, '-m', VOICE, '-f', speech.name], input=text, text=True,
                       capture_output=True, timeout=30, check=True)
        subprocess.run(['flock', VOICE_LOCK, 'timeout', '30', 'pw-play', '--target', SINK, speech.name],
                       timeout=90, check=True)


def transcribe(pcm):
    with tempfile.NamedTemporaryFile(suffix='.wav') as audio:
        with wave.open(audio.name, 'wb') as out:
            out.setnchannels(1)
            out.setsampwidth(2)
            out.setframerate(RATE)
            out.writeframes(pcm)
        result = subprocess.run([HANDY, '--transcribe-file', audio.name, '--json'],
                                capture_output=True, text=True, timeout=30, check=True)
    return json.loads(result.stdout)['text']


def signal(status):
    with open(LINE_STATUS, 'w', encoding='utf-8') as marker:
        marker.write(status)


def calls(text):
    """Return (agent, message) for each call in a line. A weak name leaves agent as None.

    A wake word starts a call once the line itself opens with one or with a name, unless
    what follows names nobody: the phrase in a sentence and a misheard name look alike, so
    the words stay in the call before it and a None entry still turns the light orange.
    All names are settled before anything is sent, so a failed decision sends nothing.
    """
    opening, *called = WAKE.split(text.strip())
    named = route(opening)
    if not named and re.search(r'\w', opening) and not STOP_WORD.fullmatch(opening):
        return []
    lines, unplaced = ([named] if named else []), []
    for part in (part.strip(' ,;:') for part in called if re.search(r'\w', part)):
        agent = closest(part)
        if agent or not lines:
            lines.append((agent, part))
        else:
            lines[-1] = (lines[-1][0], f'{lines[-1][1]} check check {part}')
            unplaced.append((None, part))
    return lines + unplaced


def send(agent, message):
    """Pass one call to its agent and return what became of it."""
    if not agent:
        print('voice-mode: line names no agent, dropped', flush=True)
        return 'dropped'
    if not registered(agent):
        signal('failed')
        say(f'Voice mode to Piotr. No agent is registered as {agent}.')
        return 'failed'
    if deliver(agent, f'{VOICE_TAG} Piotr to {agent}: {message} {VOICE_NOTE}'):
        print(f'voice-mode: line sent to {agent}', flush=True)
        return 'sent'
    signal('failed')
    say(f'Voice mode to Piotr. {agent} did not get that line.')
    return 'failed'


def handle(pcm):
    """Send one utterance to each agent it calls, and show the worst outcome."""
    text = transcribe(pcm)
    if STOP_WORD.fullmatch(text):  # check_stop already acted on it, moments earlier
        return
    outcomes = [send(agent, message) for agent, message in calls(text) or [(None, '')]]
    signal(next(status for status in ('failed', 'dropped', 'sent') if status in outcomes))


def check_wake(pcm, segmenter):
    """Light the top bar while Piotr still talks, once his line opens with the wake word.

    The line's outcome replaces the light, so a line that closed first leaves it alone.
    A failure here costs no words, the whole line is transcribed when it closes, so it
    stays off the light instead of reaching worker's red.
    """
    try:
        heard = transcribe(pcm)
    except (OSError, subprocess.SubprocessError, ValueError, KeyError) as err:
        print(f'voice-mode: opening not checked: {type(err).__name__}', file=sys.stderr, flush=True)
        return
    if WAKE.match(heard.strip()) and segmenter.utterance is not None:
        signal('armed')


def check_stop(pcm):
    """Silence every agent when a short burst is the stop word."""
    if STOP_WORD.fullmatch(transcribe(pcm)):
        silence()
        print('voice-mode: stop word heard', flush=True)


def worker(clips, act):
    """Transcribe off the capture loop, which must keep draining the mic."""
    while True:
        pcm = clips.get()
        try:
            act(pcm)
        except (OSError, subprocess.SubprocessError, ValueError, KeyError) as err:
            print(f'voice-mode: {type(err).__name__}: {err}', file=sys.stderr, flush=True)
            signal('failed')


def watch_presence():
    """Feed the bus's presence beats to PRESENCE. Without them no name resolves, so end the relay."""
    beats = subprocess.Popen([NATS, '--server', NATS_URL, 'sub', 'agents.presence', '--raw'],
                             stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    for line in beats.stdout:
        PRESENCE.beat(line)
    print('voice-mode: presence stream ended', file=sys.stderr, flush=True)
    os._exit(1)


def main():
    threading.Thread(target=watch_presence, daemon=True).start()
    utterances = queue.Queue()
    bursts = queue.Queue()  # its own worker: a slow delivery must not hold up the stop word
    openings = queue.Queue()
    segmenter = Segmenter()
    threading.Thread(target=worker, args=(utterances, handle), daemon=True).start()
    threading.Thread(target=worker, args=(bursts, check_stop), daemon=True).start()
    threading.Thread(target=worker, args=(openings, lambda pcm: check_wake(pcm, segmenter)), daemon=True).start()
    mic = subprocess.Popen(['parec', f'--device={SOURCE}', f'--rate={RATE}', '--channels=1',
                            '--format=s16le', '--latency-msec=30'], stdout=subprocess.PIPE)
    barge_in = BargeIn()
    hold_speech(False)  # a relay that died mid-line left speech paused
    while len(frame := mic.stdout.read(FRAME_BYTES)) == FRAME_BYTES:
        pcm = segmenter.push(frame)
        barge_in.update(segmenter.utterance is not None)
        if pcm:
            utterances.put(pcm)
        if burst := segmenter.burst():
            bursts.put(burst)
        if opening := segmenter.opening():
            openings.put(opening)
    sys.exit('voice-mode: microphone stream ended')


if __name__ == '__main__':
    main()
