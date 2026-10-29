#!/usr/bin/env python3
"""Test margin clipping and redraw through a private pseudo-terminal."""
import fcntl
import importlib.util
import io
import os
from pathlib import Path
import select
import signal
import struct
import subprocess
import tempfile
import termios
import time
import unittest
from unittest.mock import patch

VIEW_PATH = Path(__file__).resolve().parents[2] / 'scripts/__tmux_reading_margin_view.py'
spec = importlib.util.spec_from_file_location('margin_view', VIEW_PATH)
VIEW = importlib.util.module_from_spec(spec)
spec.loader.exec_module(VIEW)


class MarginViewTest(unittest.TestCase):
    def test_clicks_use_full_block_in_each_viewer(self):
        with tempfile.TemporaryDirectory(prefix='margin-click-') as tmp:
            root = Path(tmp)
            renderer, jump, hits = root / 'renderer', root / 'jump', root / 'hits'
            renderer.write_text('#!/bin/sh\nprintf "HEADER\\n\\nAGENT: first\\nLATEST: update\\nSTATUS: working\\nSESSION: jump:first:window\\n\\nAGENT: second\\nSTATUS: idle\\nSESSION: jump:second\\n"\nsleep 3\n')
            jump.write_text('#!/bin/sh\nprintf "%s\\n" "$1" >> "$TEST_HITS"\n')
            renderer.chmod(0o755)
            jump.chmod(0o755)
            viewers = []
            for _ in range(2):
                master, slave = os.openpty()
                fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack('HHHH', 5, 15, 0, 0))
                env = dict(os.environ, TEST_HITS=str(hits), TMUX_READING_MARGIN_JUMP_COMMAND=str(jump))
                proc = subprocess.Popen(['python3', str(VIEW_PATH), str(renderer)], stdin=slave, stdout=slave, stderr=subprocess.DEVNULL, env=env, start_new_session=True)
                os.close(slave)
                viewers.append((master, proc))
            def cleanup():
                for master, proc in viewers:
                    if proc.poll() is None:
                        proc.terminate()
                        proc.wait(timeout=3)
                    os.close(master)
            self.addCleanup(cleanup)
            def wait_text(master, needle):
                data = b''
                end = time.monotonic() + 5
                while time.monotonic() < end:
                    if needle in data:
                        return
                    ready, _, _ = select.select([master], [], [], .05)
                    if ready:
                        data += os.read(master, 65536)
                self.fail(f'no {needle!r}: {data!r}')
            def wait_hits(count):
                end = time.monotonic() + 2
                while time.monotonic() < end:
                    if hits.exists() and len(hits.read_text().splitlines()) >= count:
                        return hits.read_text().splitlines()
                    time.sleep(.01)
                self.fail('jump did not run')
            for master, _ in viewers:
                wait_text(master, b'LATEST: update')
                os.write(master, b'\x1b[<0;1;4M')
            self.assertEqual(wait_hits(2), ['jump:first:window'] * 2)
            master, _ = viewers[0]
            os.write(master, b'\x1b[<0;1;1M\x1b[<0;1;2M\x1b[<4;1;3M\x1b[<16;1;3M\x1b[<0;1;3m\x1b[<1;1;3M')
            time.sleep(.2)
            self.assertEqual(hits.read_text().splitlines(), ['jump:first:window'] * 2)
            os.write(master, b'\x1b[<65;1;1M')
            wait_text(master, b'STATUS: working')
            os.write(master, b'\x1b[<0;1;4M')
            self.assertEqual(wait_hits(3), ['jump:first:window'] * 3)
            os.write(master, b'G')
            wait_text(master, b'STATUS: idle')
            os.write(master, b'\x1b[<0;1;3M')
            self.assertEqual(wait_hits(4), ['jump:first:window'] * 3 + ['jump:second'])
            os.write(master, b'\x1b[<0;1;5M\x1b[<0;0;3M\x1b[<0;16;3M\x1b[<0;1;0M')
            time.sleep(.2)
            self.assertEqual(hits.read_text().splitlines(), ['jump:first:window'] * 3 + ['jump:second'])

    def test_clips_unicode_and_ansi_without_wrapping(self):
        rows = VIEW.physical_lines('\x1b[31m界abc\x1b[0m\n    child', 4)
        self.assertEqual(rows, [('\x1b[31m界ab', False), ('    ', False)])
        stream = io.StringIO()
        with patch.object(VIEW.sys, 'stdout', stream):
            VIEW.paint(rows, 0, 4, 3)
        self.assertIn('\x1b[1;1H\x1b[0m\x1b[31m界ab', stream.getvalue())
        self.assertIn('\x1b[2;1H\x1b[0m    ', stream.getvalue())

    def test_pty_resize_scroll_and_failure(self):
        with tempfile.TemporaryDirectory(prefix='margin-view-') as tmp:
            root = Path(tmp)
            calls, fail, started = root / 'calls', root / 'fail', root / 'started'
            renderer = root / 'renderer.py'
            renderer.write_text('''#!/usr/bin/env python3
import os, pathlib, time
calls = pathlib.Path(os.environ['TEST_CALLS'])
n = int(calls.read_text()) + 1 if calls.exists() else 1
calls.write_text(str(n))
if n > 1:
    pathlib.Path(os.environ['TEST_STARTED']).touch()
    time.sleep(1.2)
if pathlib.Path(os.environ['TEST_FAIL']).exists(): raise SystemExit(1)
print('URL: https://example.test/a-very-long-path')
print('    CHILD: fixed-left')
for i in range(12): print('ROW-%02d' % i)
''')
            renderer.chmod(0o755)
            master, slave = os.openpty()
            def resize(width, height):
                fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack('HHHH', height, width, 0, 0))
            resize(20, 6)
            env = dict(os.environ, TEST_CALLS=str(calls), TEST_FAIL=str(fail), TEST_STARTED=str(started))
            proc = subprocess.Popen(['python3', str(VIEW_PATH), str(renderer)], stdin=slave, stdout=slave, stderr=subprocess.PIPE, env=env, start_new_session=True)
            os.close(slave)
            self.addCleanup(os.close, master)
            def cleanup():
                if proc.poll() is None:
                    proc.terminate()
                    proc.wait(timeout=3)
                proc.stderr.close()
            self.addCleanup(cleanup)
            output = bytearray()
            def wait_for(needle, timeout=3):
                end = time.monotonic() + timeout
                while time.monotonic() < end:
                    if needle in output:
                        return
                    ready, _, _ = select.select([master], [], [], min(.05, max(0, end - time.monotonic())))
                    if ready:
                        output.extend(os.read(master, 65536))
                self.fail(f'missing {needle!r}; output {bytes(output)!r}')
            wait_for(b'\x1b[1;1H\x1b[0mURL: https://example')
            self.assertNotIn(b'long-path', output)
            self.assertIn(b'\x1b[2;1H\x1b[0m    CHILD: fixed-lef', output)
            deadline = time.monotonic() + 2
            while not started.exists() and time.monotonic() < deadline:
                time.sleep(.01)
            self.assertTrue(started.exists())
            output.clear()
            resize(60, 6)
            os.kill(proc.pid, signal.SIGWINCH)
            wait_for(b'URL: https://example.test/a-very-long-path', .5)
            output.clear()
            os.write(master, b'G')
            wait_for(b'ROW-11', .5)
            output.clear()
            os.write(master, b'g')
            wait_for(b'\x1b[2;1H\x1b[0m    CHILD: fixed-left', .5)
            fail.touch()
            output.clear()
            wait_for(b'Roster read failed', 3)
            os.write(master, b'q')
            proc.wait(timeout=3)
            wait_for(b'\x1b[?7h', 1)


if __name__ == '__main__':
    unittest.main()
