#!/usr/bin/env python3
"""Integration test for the work margin using an isolated tmux server."""
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import time
import unittest
import uuid
import importlib.util
import io
from unittest.mock import patch

WORK = Path(__file__).resolve().parents[2] / 'scripts/__tmux_reading_margin_work.sh'
spec = importlib.util.spec_from_file_location('margin_view', WORK.with_name('__tmux_reading_margin_view.py'))
VIEW = importlib.util.module_from_spec(spec)
spec.loader.exec_module(VIEW)

class MarginViewTest(unittest.TestCase):
    def test_a_tall_hint_remains_whole_and_can_scroll(self):
        token = 'jump:' + 'agent-' * 10
        rows = VIEW.physical_lines(token, 8)
        self.assertEqual(''.join(text for text, _ in rows), token)
        self.assertTrue(all(soft for _, soft in rows[:-1]))
        self.assertFalse(rows[-1][1])
        offset = VIEW.bottom_offset(rows, 8, 2)
        self.assertEqual(offset, len(rows) - 2)
        stream = io.StringIO()
        with patch.object(VIEW.sys, 'stdout', stream):
            VIEW.paint(rows, offset, 8, 3)
        self.assertIn(''.join(text for text, _ in rows[-2:]), stream.getvalue())

    def test_a_single_line_pane_keeps_its_content(self):
        stream = io.StringIO()
        with patch.object(VIEW.sys, 'stdout', stream):
            VIEW.paint([('LIVE', False)], 0, 10, 1)
        self.assertIn('\x1b[2JLIVE\x1b[0m\x1b[?2026l', stream.getvalue())

    def test_resize_refresh_scroll_and_failure(self):
        with tempfile.TemporaryDirectory(prefix='margin-view-test-') as tmp:
            root = Path(tmp)
            home = root / 'home'
            home.mkdir()
            (home / '.claude').mkdir()
            (home / '.claude/scripts').symlink_to(Path.home() / '.claude/scripts')
            board = root / 'board'
            slow = root / 'slow'
            started = root / 'started'
            fail = root / 'fail'
            focus = root / 'focus'
            cockpit = root / 'cockpit'
            focus.write_text('#!/bin/bash\nprintf "FOCUS HEADER\\n"\n')
            cockpit.write_text('''#!/bin/bash
if [[ -f "$TEST_SLOW" ]]; then
  : > "$TEST_STARTED"
  sleep 1.2
fi
[[ ! -f "$TEST_FAIL" ]] || exit 1
if [[ ${COCKPIT_RAW:-0} == 1 ]]; then
  cat "$TEST_BOARD"
else
  python3 "$HOME/.claude/scripts/__cockpit_wrap.py" --board "$COCKPIT_VERTICAL_WIDTH" < "$TEST_BOARD"
fi
''')
            focus.chmod(0o755)
            cockpit.chmod(0o755)
            board.write_text('COCKPIT HEADER\nAGENT:   parent\nLATEST:  alpha beta gamma delta epsilon\nSTATUS:  working\nSESSION: jump:parent\n    AGENT:   child\n    STATUS:  idle\n    SESSION: jump:child\n    PRS:     repo#123\n' + ''.join(f'AGENT:   row-{i:02d}\nSTATUS:  working\n' for i in range(16)))
            socket = 'margin-test-' + uuid.uuid4().hex
            self.addCleanup(lambda: subprocess.run(['tmux', '-L', socket, 'kill-server'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
            def tmux(*args):
                return subprocess.run(['tmux', '-L', socket, '-f', '/dev/null', *args], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True).stdout
            env = dict(os.environ, HOME=str(home), XDG_CACHE_HOME=str(root / 'cache'), XDG_RUNTIME_DIR=str(root / 'runtime'), TMUX_READING_MARGIN_COCKPIT_STATE_COMMAND=str(cockpit), TMUX_READING_MARGIN_FOCUS_COMMAND=str(focus), TEST_BOARD=str(board), TEST_SLOW=str(slow), TEST_STARTED=str(started), TEST_FAIL=str(fail))
            (root / 'runtime').mkdir()
            command = ' '.join(shlex.quote(x) for x in ['env', *[f'{k}={v}' for k,v in env.items() if k in ('HOME','XDG_CACHE_HOME','XDG_RUNTIME_DIR','TMUX_READING_MARGIN_COCKPIT_STATE_COMMAND','TMUX_READING_MARGIN_FOCUS_COMMAND','TEST_BOARD','TEST_SLOW','TEST_STARTED','TEST_FAIL')], '/bin/bash', str(WORK), 'test', '@0'])
            tmux('new-session', '-d', '-s', 'test', '-x', '74', '-y', '14', command)
            tmux('set-window-option', '-t', 'test:0', 'window-size', 'manual')
            def screen():
                return tmux('capture-pane', '-p', '-t', 'test:0.0')
            def wait_for(predicate, seconds=3):
                end = time.monotonic() + seconds
                while time.monotonic() < end:
                    text = screen()
                    if predicate(text):
                        return text
                    time.sleep(.02)
                self.fail('screen condition timed out; last screen:\n' + text)
            first = screen()
            self.assertNotIn('Loading', first)
            text = wait_for(lambda s: 'jump:child' in s and 'repo#123' in s)
            self.assertIn('    AGENT:', text)
            self.assertIn('jump:parent', text)
            # Collect once at the narrow width, then grow while the following
            # collection is blocked. Hard newlines from the narrow render must
            # not survive in the wide frame.
            tmux('resize-window', '-t', 'test:0', '-x', '23', '-y', '14')
            wait_for(lambda s: 'alpha beta' in s and 'gamma delta' in s)
            time.sleep(.3)
            # Wait until the slow collection is in flight before changing width.
            slow.touch()
            deadline = time.monotonic() + 3
            while not started.exists() and time.monotonic() < deadline:
                time.sleep(.02)
            self.assertTrue(started.exists(), 'slow collection never started')
            start = time.monotonic()
            tmux('resize-window', '-t', 'test:0', '-x', '74', '-y', '14')
            wait_for(lambda s: 'LATEST:  alpha beta gamma delta epsilon' in s, .4)
            self.assertLess(time.monotonic() - start, .4)
            start = time.monotonic()
            tmux('resize-window', '-t', 'test:0', '-x', '23', '-y', '14')
            wait_for(lambda s: 'COCKPIT HEADER' in s and 'alpha beta' in s and any('gamma' in line and 'alpha' not in line for line in s.splitlines()), .4)
            self.assertLess(time.monotonic() - start, .4)
            slow.unlink()
            tmux('resize-window', '-t', 'test:0', '-x', '74', '-y', '14')
            wait_for(lambda s: '    AGENT:   child' in s and 'repo#123' in s, 2)
            # A short pane starts at the first row and can scroll to the last.
            tmux('resize-window', '-t', 'test:0', '-x', '74', '-y', '6')
            wait_for(lambda s: 'FOCUS HEADER' in s, 1)
            tmux('send-keys', '-t', 'test:0.0', 'G')
            text = wait_for(lambda s: 'row-15' in s, 1)
            self.assertNotIn('parent', text)
            tmux('send-keys', '-t', 'test:0.0', 'k')
            tmux('send-keys', '-t', 'test:0.0', 'j')
            tmux('send-keys', '-t', 'test:0.0', 'Home')
            wait_for(lambda s: 'parent' in s, 1)
            tmux('send-keys', '-t', 'test:0.0', 'Home')
            wait_for(lambda s: 'FOCUS HEADER' in s, 1)
            tmux('send-keys', '-l', '-t', 'test:0.0', '\x1b[<65;1;1M')
            wait_for(lambda s: 'FOCUS HEADER' not in s, 1)
            tmux('send-keys', '-t', 'test:0.0', 'Home')
            wait_for(lambda s: 'FOCUS HEADER' in s, 1)
            tmux('resize-window', '-t', 'test:0', '-x', '74', '-y', '14')
            board.write_text('COCKPIT HEADER\nAGENT:   fresh-row\nSTATUS:  ready\nSESSION: jump:fresh-row\n')
            wait_for(lambda s: 'fresh-row' in s and 'ready' in s and 'parent' not in s, 1)
            fail.touch()
            wait_for(lambda s: 'fresh-row' not in s, 2)

if __name__ == '__main__':
    unittest.main()
