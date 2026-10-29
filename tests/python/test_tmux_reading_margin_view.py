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
    @classmethod
    def setUpClass(cls):
        cls.build_dir = tempfile.TemporaryDirectory(prefix='margin-build-')
        root = Path(cls.build_dir.name)
        source = root / 'main.go'
        source.write_text(VIEW_PATH.with_name('tmux_reading_margin_collect.go').read_text())
        cls.collector = root / 'collector'
        subprocess.run(['go', 'build', '-o', str(cls.collector), str(source)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.build_dir.cleanup()

    @staticmethod
    def viewer_for_collector(collector_pid, viewers):
        ppid = int(Path(f'/proc/{collector_pid}/stat').read_text().split()[3])
        return next(proc for _, proc in viewers if proc.pid == ppid)

    def test_nested_inputs_and_continuous_dirty(self):
        with tempfile.TemporaryDirectory(prefix='margin-inputs-') as tmp:
            root = Path(tmp)
            notes = root / '.claude/tmp'
            updates = notes / 'cockpit-updates'
            updates.mkdir(parents=True)
            item = updates / 'agent'
            item.write_text('old')
            calls, state, renderer = root / 'calls', root / 'state', root / 'renderer'
            renderer.write_text('#!/bin/sh\necho call >> "$CALLS"\nprintf "frame\\n"\n')
            renderer.chmod(0o755)
            master, slave = os.openpty()
            fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack('HHHH', 5, 25, 0, 0))
            env = dict(os.environ, HOME=str(root), TASKDATA=str(root / 'taskdata'), XDG_STATE_HOME=str(root / 'xdg'), HANDOFF_PROBE_STATE=str(root / 'probe/state.json'), CALLS=str(calls), TMUX_READING_MARGIN_STATE_DIR=str(state), TMUX_READING_MARGIN_COLLECT_COMMAND=str(self.collector))
            proc = subprocess.Popen(['python3', str(VIEW_PATH), str(renderer)], stdin=slave, stdout=slave, stderr=subprocess.DEVNULL, env=env, start_new_session=True)
            os.close(slave)
            def cleanup():
                if proc.poll() is None:
                    proc.terminate()
                    proc.wait(timeout=3)
                os.close(master)
            self.addCleanup(cleanup)
            def wait_calls(n, timeout=1):
                end = time.monotonic() + timeout
                while time.monotonic() < end:
                    if calls.exists() and len(calls.read_text().splitlines()) >= n:
                        return
                    time.sleep(.01)
                self.fail(f'expected {n} renders')
            wait_calls(1, 3)
            item.write_text('new')
            wait_calls(2)
            newdir = notes / 'cockpit-pr-state'
            newdir.mkdir()
            wait_calls(3)
            time.sleep(.5)
            before = len(calls.read_text().splitlines())
            for name in ('item.lock', 'item.try', 'item.tmp.123', '.hidden'):
                (newdir / name).write_text('metadata')
            time.sleep(.4)
            self.assertEqual(len(calls.read_text().splitlines()), before)
            (newdir / 'item').write_text('new')
            wait_calls(before + 1)
            # Replacing the watched root must install a new watch.
            updates.rename(notes / 'old-updates')
            updates.mkdir()
            wait_calls(before + 2)
            time.sleep(.3)
            before = len(calls.read_text().splitlines())
            (updates / 'new').write_text('value')
            wait_calls(before + 1)
            before = len(calls.read_text().splitlines())
            notes.rename(root / '.claude/old-tmp')
            notes.mkdir()
            wait_calls(before + 1)
            before = len(calls.read_text().splitlines())
            end = time.monotonic() + .7
            while time.monotonic() < end:
                (state / 'dirty').touch()
                time.sleep(.04)
            self.assertGreater(len(calls.read_text().splitlines()), before)

    def test_leader_crash_keeps_lock_until_collector_exits(self):
        with tempfile.TemporaryDirectory(prefix='margin-crash-') as tmp:
            root = Path(tmp)
            renderer, calls, state = root / 'renderer.py', root / 'calls', root / 'state'
            renderer.write_text('''#!/usr/bin/env python3
import fcntl, os, pathlib, time
lock = open(os.environ['CALLS'] + '.lock', 'w')
try: fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError: pathlib.Path(os.environ['CALLS'] + '.overlap').touch()
with open(os.environ['CALLS'], 'a') as f: f.write(str(os.getppid()) + '\\n')
time.sleep(1)
print('READY')
''')
            renderer.chmod(0o755)
            viewers = []
            for _ in range(3):
                master, slave = os.openpty()
                fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack('HHHH', 5, 25, 0, 0))
                env = dict(os.environ, XDG_STATE_HOME=str(root / 'xdg'), HANDOFF_PROBE_STATE=str(root / 'probe' / 'state.json'), HOME=str(root), TASKDATA=str(root / 'taskdata'), CALLS=str(calls), TMUX_READING_MARGIN_STATE_DIR=str(state), TMUX_READING_MARGIN_COLLECT_COMMAND=str(self.collector))
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
            deadline = time.monotonic() + 3
            while not calls.exists() and time.monotonic() < deadline:
                time.sleep(.01)
            leader_pid = int(calls.read_text().strip())
            os.kill(leader_pid, signal.SIGKILL)
            deadline = time.monotonic() + 3
            while len(calls.read_text().splitlines()) < 2 and time.monotonic() < deadline:
                time.sleep(.02)
            self.assertEqual(len(calls.read_text().splitlines()), 2)
            self.assertFalse(Path(str(calls) + '.overlap').exists())

    def test_shared_frame_scroll_and_leader_failover(self):
        with tempfile.TemporaryDirectory(prefix='margin-shared-') as tmp:
            root = Path(tmp)
            renderer, source, calls, state = root / 'renderer.py', root / 'source', root / 'calls', root / 'state'
            source.write_text('HEADER\nAGENT: one\nSTATUS: idle\nSESSION: jump:one\n' + ''.join(f'ROW-{i}\n' for i in range(12)))
            renderer.write_text('''#!/usr/bin/env python3
import os, pathlib
with open(os.environ['CALLS'], 'a') as f: f.write(str(os.getppid()) + '\\n')
print(pathlib.Path(os.environ['SOURCE']).read_text(), end='')
''')
            renderer.chmod(0o755)
            viewers = []
            for width, height in ((15, 5), (25, 7), (40, 9)):
                master, slave = os.openpty()
                fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack('HHHH', height, width, 0, 0))
                env = dict(os.environ, XDG_STATE_HOME=str(root / 'xdg'), HANDOFF_PROBE_STATE=str(root / 'probe' / 'state.json'), HOME=str(root), TASKDATA=str(root / 'taskdata'), CALLS=str(calls), SOURCE=str(source), TMUX_READING_MARGIN_STATE_DIR=str(state), TMUX_READING_MARGIN_COLLECT_COMMAND=str(self.collector))
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
            def read_until(master, needle, timeout=3):
                data, end = b'', time.monotonic() + timeout
                while time.monotonic() < end:
                    if needle in data:
                        return
                    ready, _, _ = select.select([master], [], [], .05)
                    if ready:
                        data += os.read(master, 65536)
                self.fail(f'missing {needle!r}: {data!r}')
            for master, _ in viewers:
                read_until(master, b'AGENT: one')
            time.sleep(.4)
            self.assertEqual(len(calls.read_text().splitlines()), 1)
            os.write(viewers[0][0], b'G')
            for master, _ in viewers:
                read_until(master, b'ROW-11')
            source.write_text('UPDATED\n')
            (state / 'dirty').touch()
            start = time.monotonic()
            # Return to the top so the shorter replacement frame is visible.
            os.write(viewers[0][0], b'g')
            for master, _ in viewers:
                read_until(master, b'UPDATED', 1)
            self.assertLess(time.monotonic() - start, 1)
            self.assertEqual(len(calls.read_text().splitlines()), 2)
            leader_pid = int(calls.read_text().splitlines()[0])
            leader = self.viewer_for_collector(leader_pid, viewers)
            leader.terminate()
            leader.wait(timeout=3)
            end = time.monotonic() + 3
            while len(calls.read_text().splitlines()) < 3 and time.monotonic() < end:
                time.sleep(.02)
            self.assertEqual(len(calls.read_text().splitlines()), 3)
            self.assertNotEqual(int(calls.read_text().splitlines()[-1]), leader_pid)

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
                env = dict(os.environ, HOME=str(root), TASKDATA=str(root / 'taskdata'), XDG_STATE_HOME=str(root / 'xdg'), HANDOFF_PROBE_STATE=str(root / 'probe' / 'state.json'), TEST_HITS=str(hits), TMUX_READING_MARGIN_JUMP_COMMAND=str(jump), TMUX_READING_MARGIN_STATE_DIR=str(root / 'state'), TMUX_READING_MARGIN_COLLECT_COMMAND=str(self.collector))
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
            env = dict(os.environ, HOME=str(root), TASKDATA=str(root / 'taskdata'), XDG_STATE_HOME=str(root / 'xdg'), HANDOFF_PROBE_STATE=str(root / 'probe' / 'state.json'), TEST_CALLS=str(calls), TEST_FAIL=str(fail), TEST_STARTED=str(started), TMUX_READING_MARGIN_STATE_DIR=str(root / 'state'), TMUX_READING_MARGIN_COLLECT_COMMAND=str(self.collector))
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
            (root / 'state' / 'dirty').touch()
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
            (root / 'state' / 'dirty').touch()
            output.clear()
            time.sleep(1.6)
            self.assertIn('CHILD: fixed-left', (root / 'state' / 'frame').read_text())
            os.write(master, b'q')
            proc.wait(timeout=3)
            wait_for(b'\x1b[?7h', 1)


if __name__ == '__main__':
    unittest.main()
