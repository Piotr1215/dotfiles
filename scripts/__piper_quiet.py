#!/home/decoder/.local/share/uv/tools/piper-tts/bin/python
"""Piper's own CLI, without ONNX Runtime's spinning worker threads, at the chosen voice.

Piper has no thread setting, and taskset and OMP_NUM_THREADS do not reach it. Stock,
one spoken reply took the machine to 85% and burned 23 s of CPU for 2 s of audio,
mostly threads spinning idle. These options cost 4.5 s and arrive no later.

All speech comes through here, replies and relay notices alike, so two files in the
voice state directory reach all of it from the next line, with no restart:
  tempo  Piper's length scale: below 1 is faster, above 1 is slower.
  voice  a folder name under the voices directory. A speaker that sets
         KLOD_VOICE_MODEL keeps its own voice through this swap.
A value that cannot be used is ignored, so a typo never costs the speech.
"""
import glob
import os
import sys

import onnxruntime

stock_options = onnxruntime.SessionOptions


def quiet_options():
    options = stock_options()
    options.intra_op_num_threads = 4
    options.add_session_config_entry('session.intra_op.allow_spinning', '0')
    return options


onnxruntime.SessionOptions = quiet_options


def setting(name):
    state = os.environ.get('KLOD_VOICE_STATE', os.path.expanduser('~/.local/state/klod-voice'))
    try:
        with open(os.path.join(state, name), encoding='utf-8') as value:
            return value.read().strip()
    except OSError:
        return ''


def with_settings(args):
    """Piper's arguments with the chosen voice and tempo applied."""
    args = list(args)
    voices = os.environ.get('KLOD_VOICE_DIR', os.path.expanduser('~/.local/share/piper-voices'))
    models = glob.glob(os.path.join(voices, glob.escape(setting('voice')), '*.onnx')) if setting('voice') else []
    if models and '-m' in args and 'KLOD_VOICE_MODEL' not in os.environ:
        args[args.index('-m') + 1] = models[0]
    try:
        tempo = float(setting('tempo'))
    except ValueError:
        return args
    return [*args, '--length-scale', str(tempo)] if 0.5 <= tempo <= 2 else args


if __name__ == '__main__':
    from piper.__main__ import main

    sys.argv[1:] = with_settings(sys.argv[1:])
    main()
