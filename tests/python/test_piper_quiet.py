"""The Piper launcher: real speech with no idle spinning."""
import importlib.util
import subprocess
import sys
import types
import wave
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = ROOT / 'scripts' / '__piper_quiet.py'
TOOL_PYTHON = Path.home() / '.local/share/uv/tools/piper-tts/bin/python'
MODEL = Path.home() / '.local/share/piper-voices/lessac-medium/en_US-lessac-medium.onnx'

needs_piper = pytest.mark.skipif(not (TOOL_PYTHON.exists() and MODEL.exists()), reason='piper is not installed')

# What Piper does: build its session options from the module attribute.
PROBE = """
import runpy, sys, onnxruntime
runpy.run_path(sys.argv[1])
options = onnxruntime.SessionOptions()
print(options.intra_op_num_threads, options.get_session_config_entry('session.intra_op.allow_spinning'))
"""


@needs_piper
def test_piper_gets_capped_threads_and_no_spinning():
    probe = subprocess.run([TOOL_PYTHON, '-c', PROBE, LAUNCHER], capture_output=True, text=True, check=True)
    assert probe.stdout.split() == ['4', '0']


@needs_piper
def test_the_launcher_still_makes_speech(tmp_path):
    speech = tmp_path / 'speech.wav'
    subprocess.run([LAUNCHER, '-m', MODEL, '-f', speech], input='Hello there.', text=True, capture_output=True, check=True)
    with wave.open(str(speech)) as audio:
        assert audio.getnframes() > audio.getframerate() / 4


@pytest.fixture
def settings(monkeypatch, tmp_path):
    """The launcher's settings code, with state and voices in a scratch directory."""
    monkeypatch.setitem(sys.modules, 'onnxruntime', types.SimpleNamespace(SessionOptions=object))
    spec = importlib.util.spec_from_file_location('piper_quiet', LAUNCHER)
    quiet = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(quiet)
    monkeypatch.setenv('KLOD_VOICE_STATE', str(tmp_path))
    monkeypatch.setenv('KLOD_VOICE_DIR', str(tmp_path / 'voices'))
    return quiet, tmp_path


ARGS = ['-m', 'stock.onnx', '-f', 'out.wav']


def test_no_settings_leave_piper_as_it_was(settings):
    quiet, _ = settings
    assert quiet.with_settings(ARGS) == ARGS


@pytest.mark.parametrize(('tempo', 'added'), [
    ('0.8', ['--length-scale', '0.8']),
    ('0.5', ['--length-scale', '0.5']),
    ('2', ['--length-scale', '2.0']),
    ('0.4', []),
    ('2.1', []),
    ('fast', []),
    ('nan', []),
], ids=['faster', 'fastest allowed', 'slowest allowed', 'too fast', 'too slow', 'a word', 'not a number'])
def test_tempo_becomes_the_length_scale_when_it_is_usable(settings, tempo, added):
    quiet, state = settings
    (state / 'tempo').write_text(f'{tempo}\n')
    assert quiet.with_settings(ARGS) == [*ARGS, *added]


def test_a_chosen_voice_replaces_the_model(settings):
    quiet, state = settings
    (state / 'voices' / 'ryan-medium').mkdir(parents=True)
    model = state / 'voices' / 'ryan-medium' / 'en_US-ryan-medium.onnx'
    model.touch()
    (state / 'voice').write_text('ryan-medium\n')
    assert quiet.with_settings(ARGS) == ['-m', str(model), '-f', 'out.wav']


def test_a_voice_that_is_not_installed_keeps_the_model(settings):
    quiet, state = settings
    (state / 'voice').write_text('nobody-medium')
    assert quiet.with_settings(ARGS) == ARGS


def test_voice_mode_notices_are_made_by_the_launcher(monkeypatch):
    spec = importlib.util.spec_from_file_location('voice_mode', ROOT / 'scripts' / '__voice_mode.py')
    voice = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(voice)
    commands = []
    monkeypatch.setattr(voice.subprocess, 'run', lambda command, **_: commands.append(command))
    voice.say('Voice mode to Piotr.')
    assert Path(commands[0][0]) == LAUNCHER
