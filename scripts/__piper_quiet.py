#!/home/decoder/.local/share/uv/tools/piper-tts/bin/python
"""Piper's own CLI, without ONNX Runtime's spinning worker threads.

Piper has no thread setting, and taskset and OMP_NUM_THREADS do not reach it. Stock,
one spoken reply took the machine to 85% and burned 23 s of CPU for 2 s of audio,
mostly threads spinning idle. These options cost 4.5 s and arrive no later.
"""
import onnxruntime

stock_options = onnxruntime.SessionOptions


def quiet_options():
    options = stock_options()
    options.intra_op_num_threads = 4
    options.add_session_config_entry('session.intra_op.allow_spinning', '0')
    return options


onnxruntime.SessionOptions = quiet_options

if __name__ == '__main__':
    from piper.__main__ import main

    main()
