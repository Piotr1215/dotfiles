#!/usr/bin/env python3
"""Test margin clipping and redraw through a private pseudo-terminal."""
import contextlib
import fcntl
import importlib.util
import io
import json
import os
from pathlib import Path
import select
import shlex
import sys
import signal
import sqlite3
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
    def test_scroll_down_preserves_shared_offset_in_tall_view(self):
        lines = [(str(i), False) for i in range(5)]
        for key in (b'j', b'\x1b[<65;1;1M', b' ', b'\x1b[6~'):
            self.assertEqual(VIEW.scroll(key, 2, lines, 20, 10), 2)
        self.assertEqual(VIEW.scroll(b'k', 2, lines, 20, 10), 1)
        self.assertEqual(VIEW.scroll(b'g', 2, lines, 20, 10), 0)
        self.assertEqual(VIEW.scroll(b'j', 0, lines, 20, 3), 1)

    def test_active_marker_uses_live_pane_identity(self):
        frame = ("AGENT: group\nSTATUS: summary\n\n"
                 "\x1b[32m  AGENT: duplicate\x1b[0m\nSESSION: jump:same\n\n"
                 "    AGENT: duplicate\nSESSION: jump:same\n")
        expected = frame.replace("    AGENT: duplicate", "    AGENT: * duplicate")
        self.assertEqual(VIEW.mark_active_agent(frame, '%2', ['%1', '%2']), expected)
        self.assertEqual(VIEW.mark_active_agent(frame, '%3', ['%1', '%2']), frame)
        self.assertEqual(VIEW.mark_active_agent(frame, '%1', ['%1']), frame)
        self.assertEqual(VIEW.mark_active_agent(frame, '', ['%1', '%2']), frame)

    FAMILY = ("AGENT: parent\nSESSION: jump:parent\n\n"
              "    AGENT: kid-one\n    STATUS: \x1b[0m \x1b[32mworking: tests\x1b[0m\n    SESSION: jump:kid-one\n\n"
              "    AGENT: kid-two\n    STATUS: \x1b[0m \x1b[33mwaiting: permission\x1b[0m\n    SESSION: jump:kid-two\n\n"
              "AGENT: other\nSESSION: jump:other\n")

    def test_subagents_fold_by_default_behind_one_toggle_row(self):
        shown, folds = VIEW.fold_subagents(self.FAMILY, set())
        plain = VIEW.SGR.sub('', shown).splitlines()
        self.assertEqual(plain, ['AGENT: parent', 'SESSION: jump:parent', '',
                                 '    ▸ 2 subagents: 1 working, 1 waiting', '',
                                 'AGENT: other', 'SESSION: jump:other'])
        self.assertEqual(folds, [None, None, None, 'jump:parent', None, None, None])
        self.assertIn('\x1b[33m1 waiting', shown)  # A hidden permission wait keeps its colour.
        self.assertEqual(VIEW.jump_targets(shown)[3], None)

    def test_open_parent_shows_its_subagents_under_the_toggle_row(self):
        shown, folds = VIEW.fold_subagents(self.FAMILY, {'jump:parent'})
        plain = VIEW.SGR.sub('', shown).splitlines()
        self.assertEqual(plain[3], '    ▾ 2 subagents: 1 working, 1 waiting')
        self.assertEqual(plain[4:], [''] + VIEW.SGR.sub('', self.FAMILY).splitlines()[3:])
        self.assertEqual(folds[3], 'jump:parent')
        self.assertEqual(VIEW.jump_targets(shown)[5:8], ['jump:kid-one'] * 3)

    def test_hidden_active_subagent_marks_the_toggle_row(self):
        marked = self.FAMILY.replace('    AGENT: kid-two', '    AGENT: * kid-two')
        self.assertIn('▸ * 2 subagents', VIEW.fold_subagents(marked, set())[0])
        self.assertNotIn('▾ *', VIEW.fold_subagents(marked, {'jump:parent'})[0])
        self.assertNotIn('▸ *', VIEW.fold_subagents(self.FAMILY, set())[0])

    def test_fold_leaves_frames_without_indented_agents_alone(self):
        for frame in ('URL: x\n    CHILD: fixed-left\nROW\n', 'AGENT: one\nSESSION: jump:one\n'):
            self.assertEqual(VIEW.fold_subagents(frame, set()), (frame, [None] * len(frame.splitlines())))

    def test_toggle_flips_one_key_and_opens_all_when_any_is_closed(self):
        self.assertEqual(VIEW.toggled(set(), {'a'}), {'a'})
        self.assertEqual(VIEW.toggled({'a', 'z'}, {'a'}), {'z'})
        self.assertEqual(VIEW.toggled({'a'}, {'a', 'b'}), {'a', 'b'})
        self.assertEqual(VIEW.toggled({'a', 'b', 'z'}, {'a', 'b'}), {'z'})
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'expanded'
            for data, expected in (('["a", 1]', {'a'}), ('{"a": 1}', set()), ('junk', set())):
                path.write_text(data)
                self.assertEqual(VIEW.read_expanded(path), expected)
            self.assertEqual(VIEW.read_expanded(Path(tmp) / 'missing'), set())

    def test_decode_frame_validates_metadata_and_accepts_legacy(self):
        frame = 'AGENT: one\nSESSION: jump:one\n'
        self.assertEqual(VIEW.decode_frame(json.dumps({'text': frame, 'panes': ['%1']})), (frame, ['%1']))
        self.assertEqual(VIEW.decode_frame(frame), (frame, []))
        for panes in (None, 'not-a-list', [1], ['%1', None]):
            encoded = json.dumps({'text': frame, 'panes': panes})
            self.assertEqual(VIEW.decode_frame(encoded), (encoded, []))

    def test_frame_metadata_keeps_pane_order_with_text(self):
        frame = 'AGENT: one\nSESSION: jump:one\n\nAGENT: two\nSESSION: jump:two\n'
        first = json.dumps({'text': frame, 'panes': ['%1', '%2']})
        second = json.dumps({'text': frame, 'panes': ['%2', '%1']})
        raw, panes = VIEW.decode_frame(first)
        self.assertIn('AGENT: * one', VIEW.mark_active_agent(raw, '%1', panes))
        raw, panes = VIEW.decode_frame(second)
        self.assertIn('AGENT: * two', VIEW.mark_active_agent(raw, '%1', panes))
        raw, panes = VIEW.decode_frame(first)
        self.assertIn('AGENT: * one', VIEW.mark_active_agent(raw, '%1', panes))

    def test_paint_and_scroll_use_last_row(self):
        lines = [(f'row-{i}', False) for i in range(6)]
        stream = io.StringIO()
        with patch.object(VIEW.sys, 'stdout', stream):
            VIEW.paint(lines, 0, 20, 4)
        self.assertIn('\x1b[4;1H\x1b[0mrow-3', stream.getvalue())
        self.assertNotIn('j/k scroll', stream.getvalue())
        self.assertEqual(VIEW.scroll(b'G', 0, lines, 20, 4), 2)
        self.assertEqual(VIEW.scroll(b'j', 0, lines, 20, 4), 1)
        self.assertEqual(VIEW.scroll(b'k', 1, lines, 20, 4), 0)

    @classmethod
    def setUpClass(cls):
        cls.build_dir = tempfile.TemporaryDirectory(prefix='margin-build-')
        root = Path(cls.build_dir.name)
        cls.env_patch = patch.dict(os.environ, {'TMUX_READING_MARGIN_SEMANTIC_FILTER': '0',
                                                'CYCLE_AGENT_CACHE_DIR': str(root / 'cycle')})
        cls.env_patch.start()
        source = root / 'main.go'
        source.write_text(VIEW_PATH.with_name('tmux_reading_margin_collect.go').read_text())
        cls.collector = root / 'collector'
        subprocess.run(['go', 'build', '-o', str(cls.collector), str(source)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.build_dir.cleanup()
        cls.env_patch.stop()

    @contextlib.contextmanager
    def viewer_dir(self, prefix):
        """A temp dir removed only after the registered cleanups stop the viewers.

        addCleanup runs after the test method returns, so a plain
        TemporaryDirectory was removed while viewers still wrote state into it
        (Directory not empty on the CI runner).
        """
        with tempfile.TemporaryDirectory(prefix=prefix) as tmp:
            try:
                yield tmp
            finally:
                self.doCleanups()

    def test_semantic_filter(self):
        with self.viewer_dir('margin-semantic-') as tmp:
            root = Path(tmp)
            task, state, bindir = root / 'task', root / 'state', root / 'bin'
            task.mkdir(); bindir.mkdir()
            db = task / 'taskchampion.sqlite3'
            with sqlite3.connect(db) as conn:
                conn.executescript('''create table tasks (uuid text, data text); create table working_set (id integer, uuid text); create table sync_meta (val text); insert into tasks values ('a','{"linear_issue_id":"DEVOPS-123","description":"one"}'),('b','{"linear_issue_id":"DEVOPS-999","description":"two"}'); insert into working_set values (1,'a'); insert into sync_meta values ('old');''')
            pane, calls = root / 'pane', root / 'calls'
            queries = root / 'queries'
            python = bindir / 'python3'; python.write_text('#!/bin/sh\necho query >> "$QUERIES"\nexec ' + shlex.quote(sys.executable) + ' "$@"\n'); python.chmod(0o755)
            pane.write_text('DEVOPS-123 window pane option-one\n')
            tmux = bindir / 'tmux'; tmux.write_text('#!/bin/sh\n[ ! -e "$FAIL_FINGERPRINT" ] || exit 1\ncat "$PANE"\n'); tmux.chmod(0o755)
            renderer = root / 'renderer'; renderer.write_text('#!/bin/sh\necho call >> "$CALLS"\nprintf "frame\\n"\n'); renderer.chmod(0o755)
            master, slave = os.openpty()
            fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack('HHHH', 5, 25, 0, 0))
            env = dict(os.environ, HOME=str(root), TASKDATA=str(task), XDG_STATE_HOME=str(root / 'xdg'), HANDOFF_PROBE_STATE=str(root / 'probe/state.json'), TMUX='', PATH=str(bindir) + ':' + os.environ['PATH'], PANE=str(pane), CALLS=str(calls), QUERIES=str(queries), FAIL_FINGERPRINT=str(root / 'fail'), TMUX_READING_MARGIN_STATE_DIR=str(state), TMUX_READING_MARGIN_COLLECT_COMMAND=str(self.collector), TMUX_READING_MARGIN_SEMANTIC_FILTER='1')
            env.pop('TMUX_READING_MARGIN_SEMANTIC_FILTER')
            proc = subprocess.Popen(['python3', str(VIEW_PATH), str(renderer)], stdin=slave, stdout=slave, stderr=subprocess.DEVNULL, env=env, start_new_session=True)
            os.close(slave)
            def cleanup():
                if proc.poll() is None: proc.terminate(); proc.wait(timeout=3)
                os.close(master)
            self.addCleanup(cleanup)
            def wait_calls(n):
                end = time.monotonic() + 3
                while time.monotonic() < end:
                    if calls.exists() and len(calls.read_text().splitlines()) >= n: return
                    time.sleep(.01)
                self.fail(f'expected {n} renders')
            wait_calls(1)
            time.sleep(1.2)
            query_count = len(queries.read_text().splitlines())
            (state / 'dirty').touch()
            time.sleep(1.3)
            self.assertEqual(len(queries.read_text().splitlines()), query_count)
            with sqlite3.connect(db) as conn: conn.execute("update sync_meta set val='changed'")
            (state / 'dirty').touch()
            time.sleep(.7)
            self.assertEqual(len(calls.read_text().splitlines()), 1)
            with sqlite3.connect(db) as conn:
                conn.execute('delete from tasks')
                conn.executemany('insert into tasks values (?,?)', [('b','{"linear_issue_id":"DEVOPS-999","description":"two"}'), ('a','{"linear_issue_id":"DEVOPS-123","description":"one"}')])
            time.sleep(.7)
            self.assertEqual(len(calls.read_text().splitlines()), 1)
            with sqlite3.connect(db) as conn: conn.execute("update tasks set data='{\"linear_issue_id\":\"DEVOPS-999\",\"description\":\"unrelated\"}' where uuid='b'")
            time.sleep(1.2)
            self.assertEqual(len(calls.read_text().splitlines()), 1)
            with sqlite3.connect(db) as conn: conn.execute("update tasks set data='{\"linear_issue_id\":\"DEVOPS-123\",\"description\":\"changed\"}' where uuid='a'")
            wait_calls(2)
            self.assertEqual(len(queries.read_text().splitlines()), query_count, 'SQLite reader must be reused after a database change')
            pane.write_text('DEVOPS-123 window pane option-two\n')
            (state / 'dirty').touch()
            wait_calls(3)
            updates = root / '.claude/tmp/cockpit-updates'
            updates.mkdir(parents=True)
            note = updates / 'agent.txt'
            note.write_text('first')
            wait_calls(4)
            note.write_text('first\nignored second line')
            (updates / 'ignored.data').write_text('ignored')
            time.sleep(1.5)
            self.assertEqual(len(calls.read_text().splitlines()), 4)
            replacement = updates / '.new'
            replacement.write_text('second')
            replacement.replace(note)
            wait_calls(5)
            note.unlink()
            wait_calls(6)
            note.write_text('input | waiting for answer')
            wait_calls(7)
            before = note.stat().st_mtime
            os.utime(note, (before + 5, before + 5))
            wait_calls(8)
            note.unlink()
            wait_calls(9)
            time.sleep(1.2)
            self.assertEqual(len(calls.read_text().splitlines()), 9)
            (root / 'fail').touch()
            pane.write_text('DEVOPS-123 window pane option-three\n')
            (state / 'dirty').touch()
            end = time.monotonic() + 3
            while not (state / 'fingerprint-error').exists() and time.monotonic() < end:
                time.sleep(.02)
            self.assertTrue((state / 'fingerprint-error').exists())
            time.sleep(.5)
            wait_calls(10)
            (root / 'fail').unlink()
            wait_calls(11)
            (updates / 'DEVOPS-999.txt').write_text('working | active | pr=org/repo#42')
            pane.write_text('repo-pr-42\x1fwindow\x1f%1\x1f1\x1fshell\x1f\x1f\n')
            (state / 'dirty').touch()
            wait_calls(12)
            with sqlite3.connect(db) as conn: conn.execute("update tasks set data='{\"linear_issue_id\":\"DEVOPS-999\",\"description\":\"pr title\"}' where uuid='b'")
            wait_calls(13)
            with sqlite3.connect(db) as conn: conn.execute("update tasks set data='invalid json' where uuid='a'")
            wait_calls(14)
            self.assertTrue((state / 'fingerprint-error').exists())
            with sqlite3.connect(db) as conn: conn.execute("update tasks set data='{}' where uuid='a'")
            end = time.monotonic() + 4
            while (state / 'fingerprint-error').exists() and time.monotonic() < end:
                time.sleep(.02)
            self.assertFalse((state / 'fingerprint-error').exists())

    @staticmethod
    def viewer_for_collector(collector_pid, viewers):
        ppid = int(Path(f'/proc/{collector_pid}/stat').read_text().split()[3])
        return next(proc for _, proc in viewers if proc.pid == ppid)

    def test_nested_inputs_and_continuous_dirty(self):
        with self.viewer_dir('margin-inputs-') as tmp:
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
            def wait_calls(n, timeout=3):
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
            self.assertEqual(len(calls.read_text().splitlines()), before)
            wait_calls(before + 1)
            self.assertEqual(len(calls.read_text().splitlines()), before + 1)
            before = len(calls.read_text().splitlines())
            started = time.monotonic()
            while time.monotonic() - started < 5.3:
                (state / 'dirty').touch()
                time.sleep(.08)
            self.assertGreater(len(calls.read_text().splitlines()), before)

    def test_safety_refresh_and_renderer_failure_recovery(self):
        with self.viewer_dir('margin-refresh-') as tmp:
            root = Path(tmp)
            calls, state, renderer = root / 'calls', root / 'state', root / 'renderer'
            renderer.write_text('#!/bin/sh\necho call >> "$CALLS"\n[ -e "$FAIL" ] && exit 1\nprintf "recovered frame\\n"\n')
            renderer.chmod(0o755)
            fail = root / 'fail'
            fail.touch()
            master, slave = os.openpty()
            fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack('HHHH', 5, 25, 0, 0))
            env = dict(os.environ, HOME=str(root), TASKDATA=str(root / 'taskdata'),
                       XDG_STATE_HOME=str(root / 'xdg'), CALLS=str(calls), FAIL=str(fail),
                       TMUX_READING_MARGIN_STATE_DIR=str(state), TMUX_READING_MARGIN_COLLECT_COMMAND=str(self.collector))
            proc = subprocess.Popen(['python3', str(VIEW_PATH), str(renderer)], stdin=slave, stdout=slave,
                                    stderr=subprocess.DEVNULL, env=env, start_new_session=True)
            os.close(slave)
            def cleanup():
                if proc.poll() is None:
                    proc.terminate()
                    proc.wait(timeout=3)
                os.close(master)
            self.addCleanup(cleanup)
            def wait_for(predicate, timeout):
                end = time.monotonic() + timeout
                while time.monotonic() < end:
                    if predicate(): return
                    time.sleep(.05)
                self.fail('collector did not refresh')
            wait_for(lambda: calls.exists() and calls.read_text().count('call') >= 1, 4)
            fail.unlink()
            wait_for(lambda: (state / 'frame').exists() and 'recovered frame' in (state / 'frame').read_text(), 5)
            count = calls.read_text().count('call')
            wait_for(lambda: calls.read_text().count('call') > count, 64)

    def test_leader_crash_keeps_lock_until_collector_exits(self):
        with self.viewer_dir('margin-crash-') as tmp:
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
        with self.viewer_dir('margin-shared-') as tmp:
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
            frame = json.loads((state / 'frame').read_text())
            self.assertEqual(frame['panes'], [])  # Renderer did not publish an order.
            self.assertEqual(frame['text'], source.read_text())
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
                read_until(master, b'UPDATED', 3)
            self.assertLess(time.monotonic() - start, 5)
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

    def test_viewer_focus_is_independent_and_does_not_collect(self):
        with tempfile.TemporaryDirectory(prefix='margin-focus-') as tmp:
            root = Path(tmp)
            state, calls, tmux_calls = root / 'state', root / 'calls', root / 'tmux-calls'
            state.mkdir()
            order = root / 'renderer-order'
            order.write_text('%1\n%2\n')
            renderer = root / 'renderer'
            frame = 'AGENT: one\nSESSION: jump:same\n\nAGENT: two\nSESSION: jump:same\n'
            renderer.write_text('#!/bin/sh\necho call >> "$CALLS"\ncat "$ORDER" > "$COCKPIT_ORDER_FILE"\nprintf "AGENT: one\\nSESSION: jump:same\\n\\nAGENT: two\\nSESSION: jump:same\\n"\n')
            renderer.chmod(0o755)
            bindir = root / 'bin'
            bindir.mkdir()
            tmux = bindir / 'tmux'
            tmux.write_text('#!/bin/sh\necho call >> "$TMUX_CALLS"\nprintf "%s\\n" "$INITIAL_PANE"\n')
            tmux.chmod(0o755)
            viewers = []
            for window, pane in (('@1', '%1'), ('@2', '%2')):
                master, slave = os.openpty()
                fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack('HHHH', 8, 40, 0, 0))
                env = dict(os.environ, HOME=str(root), TASKDATA=str(root / 'taskdata'),
                           XDG_STATE_HOME=str(root / 'xdg'), HANDOFF_PROBE_STATE=str(root / 'probe/state.json'),
                           PATH=str(bindir) + ':' + os.environ['PATH'], CALLS=str(calls), TMUX_CALLS=str(tmux_calls),
                           INITIAL_PANE=pane, ORDER=str(order), TMUX_READING_MARGIN_WINDOW=window,
                           TMUX_READING_MARGIN_STATE_DIR=str(state),
                           TMUX_READING_MARGIN_COLLECT_COMMAND=str(self.collector))
                proc = subprocess.Popen(['python3', str(VIEW_PATH), str(renderer)], stdin=slave,
                                        stdout=slave, stderr=subprocess.DEVNULL, env=env, start_new_session=True)
                os.close(slave)
                viewers.append((master, proc))
            def cleanup():
                for master, proc in viewers:
                    if proc.poll() is None:
                        proc.terminate()
                        proc.wait(timeout=3)
                    os.close(master)
            self.addCleanup(cleanup)
            def wait_text(master, needle, timeout=3):
                data = b''
                end = time.monotonic() + timeout
                while time.monotonic() < end:
                    ready, _, _ = select.select([master], [], [], .05)
                    if ready:
                        data += os.read(master, 65536)
                        if needle in data:
                            return data
                self.fail(f'missing {needle!r}: {data!r}')
            first = wait_text(viewers[0][0], b'AGENT: * one')
            second = wait_text(viewers[1][0], b'AGENT: * two')
            self.assertNotIn(b'AGENT: * two', first)
            self.assertNotIn(b'AGENT: * one', second)
            time.sleep(.3)
            self.assertEqual(len(tmux_calls.read_text().splitlines()), 2)
            self.assertEqual(len(calls.read_text().splitlines()), 1)
            self.assertEqual(VIEW.decode_frame((state / 'frame').read_text()), (frame, ['%1', '%2']))
            # A changed side file must not alter the order stored in this frame.
            (state / 'pane-order').write_text('%2\n%1\n')
            (state / 'active-@1').write_text('%2\n')
            wait_text(viewers[0][0], b'AGENT: * two', 1)
            (state / 'active-@2').write_text('%1\n')
            wait_text(viewers[1][0], b'AGENT: * one', 1)
            time.sleep(.3)
            self.assertEqual(len(tmux_calls.read_text().splitlines()), 2)
            self.assertEqual(len(calls.read_text().splitlines()), 1)
            self.assertEqual(VIEW.decode_frame((state / 'frame').read_text()), (frame, ['%1', '%2']))

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
            os.write(master, b'\x1b[<0;1;5M')
            self.assertEqual(wait_hits(5), ['jump:first:window'] * 3 + ['jump:second'] * 2)
            os.write(master, b'\x1b[<0;1;6M\x1b[<0;0;3M\x1b[<0;16;3M\x1b[<0;1;0M')
            time.sleep(.2)
            self.assertEqual(hits.read_text().splitlines(), ['jump:first:window'] * 3 + ['jump:second'] * 2)

    def test_click_and_s_toggle_shared_subagent_fold(self):
        with self.viewer_dir('margin-fold-') as tmp:
            root = Path(tmp)
            state, jump, hits, source = root / 'state', root / 'jump', root / 'hits', root / 'source'
            source.write_text(self.FAMILY)
            renderer = root / 'renderer'
            renderer.write_text('#!/bin/sh\ncat "$SOURCE"\n')
            jump.write_text('#!/bin/sh\nprintf "%s\\n" "$1" >> "$TEST_HITS"\n')
            renderer.chmod(0o755)
            jump.chmod(0o755)
            master, slave = os.openpty()
            fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack('HHHH', 20, 50, 0, 0))
            env = dict(os.environ, HOME=str(root), TASKDATA=str(root / 'taskdata'), XDG_STATE_HOME=str(root / 'xdg'), HANDOFF_PROBE_STATE=str(root / 'probe' / 'state.json'), SOURCE=str(source), TEST_HITS=str(hits), TMUX_READING_MARGIN_JUMP_COMMAND=str(jump), TMUX_READING_MARGIN_STATE_DIR=str(state), TMUX_READING_MARGIN_COLLECT_COMMAND=str(self.collector))
            proc = subprocess.Popen(['python3', str(VIEW_PATH), str(renderer)], stdin=slave, stdout=slave, stderr=subprocess.DEVNULL, env=env, start_new_session=True)
            os.close(slave)
            def cleanup():
                if proc.poll() is None:
                    proc.terminate()
                    proc.wait(timeout=3)
                os.close(master)
            self.addCleanup(cleanup)
            def wait_text(needle):
                data, end = b'', time.monotonic() + 3
                while time.monotonic() < end:
                    ready, _, _ = select.select([master], [], [], .05)
                    if ready:
                        data += os.read(master, 65536)
                        if needle in data:
                            return data.rsplit(b'\x1b[2J', 1)[-1]  # The last painted frame.
                self.fail(f'missing {needle!r}: {data!r}')
            self.assertNotIn(b'kid-one', wait_text('▸ 2 subagents'.encode()))
            os.write(master, b'\x1b[<0;5;4M')
            self.assertIn('▾ 2 subagents'.encode(), wait_text(b'AGENT: kid-one'))
            self.assertEqual(json.loads((state / 'expanded').read_text()), ['jump:parent'])
            os.write(master, b's')
            self.assertNotIn(b'kid-one', wait_text('▸ 2 subagents'.encode()))
            self.assertEqual(json.loads((state / 'expanded').read_text()), [])
            self.assertFalse(hits.exists())  # The toggle row never jumps.

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
            self.assertIn('CHILD: fixed-left', VIEW.decode_frame((root / 'state' / 'frame').read_text())[0])
            os.write(master, b'q')
            proc.wait(timeout=3)
            wait_for(b'\x1b[?7h', 1)


if __name__ == '__main__':
    unittest.main()
