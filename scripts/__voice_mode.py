#!/usr/bin/env python3
"""Voice mode: hear Piotr on the headset and type named lines into agent panes.

A line that opens with an agent's name ("Claude 2, run the tests") goes to the
tmux pane whose @agent_name matches it. All other speech is transcribed locally
and dropped. Run by voice-mode.service, switched from the toggle board.

Permission prompts stay keyboard-only: a pane showing one has no empty composer,
so nothing is typed into it and Enter can never answer it.

Handy must stay on the system default mic, with the headset as that default.
A selected mic is opened raw, which fails while this stream holds the device,
and Handy then erases the selection.
"""
import array
import collections
import fcntl
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
VOICE = os.path.expanduser('~/.local/share/piper-voices/lessac-medium/en_US-lessac-medium.onnx')
VOICE_LOCK = os.path.expanduser('~/.local/state/klod-voice.lock')

RATE = 16000
FRAME_BYTES = 960  # 30 ms of s16le mono

# The headset gates silence to zero; measured speech runs at 300 to 800 RMS.
SPEECH_RMS = 100
START_FRAMES = 3  # 90 ms of speech opens an utterance
END_FRAMES = 40  # 1.2 s of quiet closes it
MIN_VOICED = 10  # shorter than 300 ms of speech is a click or a cough
PRE_ROLL = 15  # 450 ms kept up to the onset, so first words survive
MAX_FRAMES = 1000  # 30 s

READY_WAIT_SECONDS = 20

# Parakeet hears "klod" as cloud or plot, and Piotr's "Claude 2" as "Claude too".
# Cloud and plot are everyday words, so they need a real number; "cloud to edge"
# is not an address. Codex needs a pause after its name.
ADDRESS = re.compile(
    r'^\W*(?:hey\W+)?(?:(?:claude|klod|clod)\W*(\d|one|won|two|to|too)\b'
    r'|(?:cloud|plot)\W*(\d|one|two)\b|(codex)\s*[,.:;!?])\W*(.*)$',
    re.IGNORECASE | re.DOTALL,
)
SPOKEN_DIGITS = {'one': '1', 'won': '1', 'two': '2', 'to': '2', 'too': '2'}
EMPTY_COMPOSER = {'', 'Press up to edit queued messages', 'Ask Codex to do anything'}


def route(text):
    """Return (agent, message) when the line opens with an agent's name."""
    match = ADDRESS.match(text.strip())
    if not match or not match[4]:
        return None
    if match[3]:
        return 'codex', match[4]
    number = (match[1] or match[2]).lower()
    return f'klod{SPOKEN_DIGITS.get(number, number)}', match[4]


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


def composer_ready(capture, cursor_y):
    """True when the pane shows an empty composer: Claude's box, or Codex's cursor row."""
    clean = lambda row: row.replace(' ', ' ').strip()
    rows = capture.split('\n')
    rules = [i for i, row in enumerate(rows) if row.startswith('─────')]
    if len(rules) >= 2:
        first, *rest = rows[rules[-2] + 1:rules[-1]] or ['']
        return first.startswith('❯') and clean(first[1:]) in EMPTY_COMPOSER and not any(map(clean, rest))
    row = rows[cursor_y] if cursor_y < len(rows) else ''
    return row.startswith('›') and clean(row[1:]) in EMPTY_COMPOSER


def tmux(*args):
    return subprocess.run(['tmux', *args], capture_output=True, text=True, check=True).stdout


def panes():
    """Map registered agent names to their pane ids."""
    named = tmux('list-panes', '-a', '-F', '#{@agent_name} #{pane_id}')
    return dict(row.split() for row in named.splitlines() if len(row.split()) == 2)


def deliver(pane, text):
    """Type text into the pane once its composer is empty, then submit it.

    Enter is sent once and never retried: a dialog that opened in between would
    take a second Enter as approval.
    """
    for attempt in range(READY_WAIT_SECONDS):
        cursor = int(tmux('display-message', '-p', '-t', pane, '#{cursor_y}'))
        if composer_ready(tmux('capture-pane', '-p', '-t', pane), cursor):
            tmux('set-option', '-p', '-t', pane, '@agent_injected_at', str(int(time.time())))
            tmux('send-keys', '-t', pane, '-l', '--', text)
            tmux('send-keys', '-t', pane, 'Enter')
            return True
        time.sleep(1)
    return False


def speaking():
    """True while an agent holds the shared speech lock."""
    with open(VOICE_LOCK, 'a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return True
    return False


def say(text):
    with tempfile.NamedTemporaryFile(suffix='.wav') as speech:
        subprocess.run(['piper', '-m', VOICE, '-f', speech.name], input=text, text=True,
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


def handle(pcm):
    """Send one utterance to the agent it names, if it names one."""
    addressed = route(transcribe(pcm))
    if not addressed:
        print('voice-mode: line names no agent, dropped', flush=True)
        return
    agent, message = addressed
    pane = panes().get(agent)
    if not pane:
        say(f'Voice mode to Piotr. No pane is named {agent}.')
    elif deliver(pane, f'Piotr to {agent} (voice): {message}'):
        print(f'voice-mode: line sent to {agent}', flush=True)
    else:
        say(f'Voice mode to Piotr. {agent} is not ready, so that line was dropped.')


def worker(utterances):
    """Transcribe off the capture loop, which must keep draining the mic."""
    while True:
        pcm = utterances.get()
        try:
            handle(pcm)
        except (OSError, subprocess.SubprocessError, ValueError, KeyError) as err:
            print(f'voice-mode: {type(err).__name__}: {err}', file=sys.stderr, flush=True)


def main():
    utterances = queue.Queue()
    threading.Thread(target=worker, args=(utterances,), daemon=True).start()
    mic = subprocess.Popen(['parec', f'--device={SOURCE}', f'--rate={RATE}', '--channels=1',
                            '--format=s16le', '--latency-msec=30'], stdout=subprocess.PIPE)
    segmenter = Segmenter()
    while len(frame := mic.stdout.read(FRAME_BYTES)) == FRAME_BYTES:
        pcm = segmenter.push(frame)
        if pcm and not speaking():
            utterances.put(pcm)
    sys.exit('voice-mode: microphone stream ended')


if __name__ == '__main__':
    main()
