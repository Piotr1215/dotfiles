"""Exercise the real configured Neovim save, refresh and close path headlessly."""
import fcntl
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
EDITOR = ROOT / 'scripts/__handoff_editor.sh'
FLOATER = ROOT / 'scripts/__handoff_floater_file.py'
UUID = '12345678-1234-1234-1234-123456789abc'


@unittest.skipUnless(shutil.which('nvim') and shutil.which('inotifywait'), 'needs Neovim and inotifywait')
class HandoffEditorLiveTest(unittest.TestCase):
    def test_edit_refresh_save_and_hide(self):
        with tempfile.TemporaryDirectory(prefix='brief-pane-') as directory:
            base = Path(directory)
            state = base / 'state'
            runtime = base / 'runtime'
            (runtime / 'taskwarrior-tui').mkdir(parents=True)
            brief_dir = state / 'taskwarrior/briefs' / UUID
            brief_dir.mkdir(parents=True)
            brief = brief_dir / 'brief.md'
            brief.write_text(
                'Your step: review\n\n# Handoff\n\n## Draft\n\n<!-- begin generated draft -->\nold draft\n'
                '<!-- end generated draft -->\n\n## Details\n\nKeep me\n'
            )
            export = base / 'task.json'
            task = {'uuid': UUID, 'description': 'Handoff', 'tags': ['piotr', 'draft'],
                    'annotations': [{'entry': '20261106T120000Z', 'description': 'draft: new draft'}]}
            export.write_text(json.dumps([task]))
            log = base / 'actions.jsonl'
            mock_task = base / 'task'
            mock_task.write_text(
                '#!/usr/bin/env python3\n'
                'import json, os, pathlib, sys\n'
                'p=pathlib.Path(os.environ["TASK_EXPORT"]); rows=json.loads(p.read_text())\n'
                'if sys.argv[-1] == "export": print(p.read_text())\n'
                'else:\n rows[0].setdefault("annotations",[]).append({"description":sys.argv[-1]})\n p.write_text(json.dumps(rows))\n'
            )
            mock_task.chmod(0o755)
            tw = base / 'tw'
            tw.write_text(
                '#!/usr/bin/env python3\n'
                'import json, os, subprocess, sys\n'
                'with open(os.environ["ACTIONS"], "a") as f: f.write(json.dumps(["note",sys.argv[1:]])+"\\n")\n'
                'subprocess.run([os.environ["HANDOFF_TASK_COMMAND"],*sys.argv[1:]],check=True)\n'
            )
            tw.chmod(0o755)
            sender = base / 'snd'
            sender.write_text(
                '#!/usr/bin/env python3\n'
                'import json, os, sys\n'
                'with open(os.environ["ACTIONS"], "a") as f: f.write(json.dumps(["dm",sys.argv[1:],os.environ.get("SND_FROM")])+"\\n")\n'
            )
            sender.chmod(0o755)
            nvim = base / 'nvim-headless'
            nvim.write_text(f'#!/usr/bin/env bash\nexec {shutil.which("nvim")} --headless "$@"\n')
            nvim.chmod(0o755)
            env = dict(os.environ, XDG_STATE_HOME=str(state), XDG_RUNTIME_DIR=str(runtime),
                       HANDOFF_ROOT=str(ROOT / 'scripts'), HANDOFF_ORIGIN='%7', HANDOFF_UUID=UUID,
                       HANDOFF_PINNED='0', HANDOFF_TASK_COMMAND=str(mock_task),
                       HANDOFF_TW_WRAPPER=str(tw), HANDOFF_SND_COMMAND=str(sender),
                       HANDOFF_NVIM_COMMAND=str(nvim), HANDOFF_SAVE_SCRIPT=str(ROOT / 'scripts/__handoff_brief_save.py'),
                       HANDOFF_BRIEF_RENDERER=str(Path.home() / '.claude/scripts/__tw_brief.py'),
                       TASK_EXPORT=str(export), ACTIONS=str(log))
            process = subprocess.Popen([str(EDITOR), str(brief)], env=env,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            socket = runtime / 'taskwarrior-tui/handoff-7.sock'

            def rpc(expression):
                return subprocess.run([str(nvim), '--server', str(socket), '--remote-expr', expression],
                                      env=env, capture_output=True, text=True, timeout=10, check=True).stdout.strip()

            try:
                self.wait_for(lambda: socket.exists())
                self.assertNotIn('HandoffHide', rpc('maparg("q", "n")'))
                buffer = json.loads(rpc("json_encode(getline(1, '$'))"))
                self.assertIn('## My comments', buffer)
                self.assertLess(buffer.index('# Handoff'), buffer.index('## My comments'))
                self.assertNotIn('<!-- begin task details -->', buffer)
                rpc("execute('call append(search(\"^## My comments$\"), \"my saved comment\")')")

                generated = subprocess.run(
                    [sys.executable, str(Path.home() / '.claude/scripts/__tw_brief.py'),
                     '--uuid', UUID, '--brief', 'Fresh generated status'],
                    input=json.dumps([task]), env=env, capture_output=True, text=True, check=True,
                )
                self.assertEqual(generated.stdout.strip(), str(brief))
                self.assertTrue((brief_dir / '.generated-pending.md').exists())
                self.assertNotIn('my saved comment', brief.read_text())
                self.assertIn('my saved comment', rpc("json_encode(getline(1, '$'))"))

                # Generation is deferred while the configured editor holds the shared lock.
                refresh = subprocess.run([sys.executable, str(FLOATER), UUID], env=env,
                                         capture_output=True, text=True, check=True)
                self.assertTrue((brief_dir / '.prepare-pending').exists())
                self.assertIn('old draft', brief.read_text())
                self.assertIn('my saved comment', rpc("json_encode(getline(1, '$'))"))

                rpc("execute('write')")
                try:
                    self.wait_for(lambda: log.exists() and len(log.read_text().splitlines()) == 2)
                except AssertionError as error:
                    self.fail(f'{error}; buffer={rpc("json_encode(getline(1, \"$\"))")}; '
                              f'brief={brief.read_text()}; log={log.read_text() if log.exists() else "missing"}')
                rows = [json.loads(line) for line in log.read_text().splitlines()]
                self.assertEqual([row[0] for row in rows], ['note', 'dm'])
                self.assertIn('+my saved comment', rows[0][1][2])
                self.assertEqual(rows[1][2], 'handoffs-file')

                # HandoffHide must return its RPC response before the deferred quit.
                self.assertIn('true', rpc("luaeval('HandoffHide()')").lower())
                code = process.wait(timeout=10)
                stdout, stderr = process.communicate(timeout=2)
                self.assertEqual(code, 0, stderr or stdout)
                refreshed = brief.read_text()
                self.assertIn('<!-- begin generated draft -->\n```\nnew draft\n```\n<!-- end generated draft -->', refreshed)
                self.assertIn('## Previous edited draft\n\nold draft', refreshed)
                self.assertIn('my saved comment', refreshed)
                self.assertFalse((brief_dir / '.prepare-pending').exists())
            finally:
                if process.poll() is None and socket.exists():
                    try:
                        rpc("execute('qa!')")
                    except Exception:
                        pass
                if process.poll() is None:
                    process.wait(timeout=5)

    def test_regular_task_shows_details_and_comment_becomes_annotation(self):
        with tempfile.TemporaryDirectory(prefix='brief-pane-') as directory:
            base = Path(directory)
            state, runtime = base / 'state', base / 'runtime'
            (runtime / 'taskwarrior-tui').mkdir(parents=True)
            export, log = base / 'task.json', base / 'actions.jsonl'
            task = {'uuid': UUID, 'description': 'Write the controllers post', 'project': 'blog',
                    'tags': ['work'], 'status': 'pending', 'due': '20261110T090000Z',
                    'annotations': [{'entry': '20261101T100000Z', 'description': 'first note'}]}
            export.write_text(json.dumps([task]))
            env = self.tool_env(base, state, runtime, export, log)
            brief = Path(subprocess.run([sys.executable, str(FLOATER), UUID], env=env, capture_output=True,
                                        text=True, check=True).stdout.strip())
            process = subprocess.Popen([str(EDITOR), str(brief)], env=env,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            socket = runtime / 'taskwarrior-tui/handoff-7.sock'

            def rpc(expression):
                return subprocess.run([env['HANDOFF_NVIM_COMMAND'], '--server', str(socket), '--remote-expr',
                                       expression], env=env, capture_output=True, text=True, timeout=10,
                                      check=True).stdout.strip()

            def buffer():
                return json.loads(rpc("json_encode(getline(1, '$'))"))

            try:
                self.wait_for(lambda: socket.exists())
                lines = buffer()
                start, end = lines.index('<!-- begin task details -->'), lines.index('<!-- end task details -->')
                details = lines[start:end]
                self.assertLess(lines.index('# Write the controllers post'), start)
                self.assertLess(end, lines.index('## My comments'))
                for line in ('- Project: blog', '- Tags: work', '- Status: pending', '- Due: 2026-11-10 09:00',
                             '- Scheduled: none', '- 2026-11-01 10:00 first note'):
                    self.assertIn(line, details)
                # Viewing a task writes the details instead of leaving the buffer modified.
                self.assertEqual(rpc('&modified'), '0')
                self.assertIn('- Project: blog', brief.read_text())

                task['annotations'].append({'entry': '20261105T100000Z', 'description': 'newest note'})
                export.write_text(json.dumps([task]))
                self.assertIn('true', rpc(f"luaeval('HandoffSwitch(_A, true)', '{UUID}')").lower())
                lines = buffer()
                details = lines[lines.index('<!-- begin task details -->'):lines.index('<!-- end task details -->')]
                self.assertEqual(details[-2:], ['- 2026-11-01 10:00 first note', '- 2026-11-05 10:00 newest note'])
                self.assertEqual(lines.count('<!-- begin task details -->'), 1)

                rpc("execute('call append(search(\"^## My comments$\"), \"remember the demo\")')")
                rpc("execute('write')")
                self.wait_for(lambda: log.exists() and len(log.read_text().splitlines()) == 2)
                rows = [json.loads(line) for line in log.read_text().splitlines()]
                self.assertEqual([row[0] for row in rows], ['note', 'dm'])
                self.assertIn('+remember the demo', rows[0][1][2])
                self.assertIn(f'Piotr commented on task {UUID}', rows[1][1][-1])

                self.assertIn('true', rpc("luaeval('HandoffHide()')").lower())
                code = process.wait(timeout=10)
                stdout, stderr = process.communicate(timeout=2)
                self.assertEqual(code, 0, stderr or stdout)
                self.assertIn('- 2026-11-05 10:00 newest note', brief.read_text())
            finally:
                if process.poll() is None and socket.exists():
                    try:
                        rpc("execute('qa!')")
                    except Exception:
                        pass
                if process.poll() is None:
                    process.wait(timeout=5)

    def tool_env(self, base, state, runtime, export, log):
        """Fake task, tw, snd and headless nvim commands around the real scripts."""
        commands = {
            'task': 'import json, os, pathlib, sys\n'
                    'p=pathlib.Path(os.environ["TASK_EXPORT"]); rows=json.loads(p.read_text())\n'
                    'if sys.argv[-1] == "export": print(p.read_text())\n'
                    'else:\n rows[0].setdefault("annotations",[]).append({"description":sys.argv[-1]})\n'
                    ' p.write_text(json.dumps(rows))\n',
            'tw': 'import json, os, subprocess, sys\n'
                  'with open(os.environ["ACTIONS"], "a") as f: f.write(json.dumps(["note",sys.argv[1:]])+"\\n")\n'
                  'subprocess.run([os.environ["HANDOFF_TASK_COMMAND"],*sys.argv[1:]],check=True)\n',
            'snd': 'import json, os, sys\n'
                   'with open(os.environ["ACTIONS"], "a") as f: '
                   'f.write(json.dumps(["dm",sys.argv[1:],os.environ.get("SND_FROM")])+"\\n")\n',
        }
        for name, body in commands.items():
            (base / name).write_text('#!/usr/bin/env python3\n' + body)
            (base / name).chmod(0o755)
        nvim = base / 'nvim-headless'
        nvim.write_text(f'#!/usr/bin/env bash\nexec {shutil.which("nvim")} --headless "$@"\n')
        nvim.chmod(0o755)
        return dict(os.environ, XDG_STATE_HOME=str(state), XDG_RUNTIME_DIR=str(runtime), TZ='UTC',
                    HANDOFF_ROOT=str(ROOT / 'scripts'), HANDOFF_ORIGIN='%7', HANDOFF_UUID=UUID,
                    HANDOFF_PINNED='0', HANDOFF_TASK_COMMAND=str(base / 'task'),
                    HANDOFF_TW_WRAPPER=str(base / 'tw'), HANDOFF_SND_COMMAND=str(base / 'snd'),
                    HANDOFF_NVIM_COMMAND=str(nvim),
                    HANDOFF_SAVE_SCRIPT=str(ROOT / 'scripts/__handoff_brief_save.py'),
                    HANDOFF_BRIEF_RENDERER=str(Path.home() / '.claude/scripts/__tw_brief.py'),
                    TASK_EXPORT=str(export), ACTIONS=str(log))

    def wait_for(self, predicate, timeout=10):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.05)
        self.fail('condition did not become true before timeout')


@unittest.skipUnless(Path('/proc/self/fd').is_dir() and shutil.which('flock'), 'needs /proc and flock')
class HandoffEditorLockTest(unittest.TestCase):
    """The wrapper holds the brief lock for the edit, but the editor's children never do."""

    def test_editor_children_do_not_hold_the_brief_lock(self):
        with tempfile.TemporaryDirectory(prefix='brief-lock-') as directory:
            base = Path(directory)
            state = base / 'state'
            lock = state / 'taskwarrior/briefs/.editor.lock'
            probe = base / 'probe'
            linger_pid = base / 'linger.pid'
            noop = base / 'noop.py'
            noop.write_text('')
            # Stands in for nvim: reports whether fd 9 came along and whether the
            # wrapper still holds the lock, then leaves a child behind the way
            # nvim's xsel clipboard child outlives the editor.
            editor = base / 'fake-nvim'
            editor.write_text(
                '#!/usr/bin/env bash\n'
                'if [ -e /proc/self/fd/9 ]; then echo inherited; else echo closed; fi > "$PROBE"\n'
                'if flock -xn "$LOCK" true; then echo free; else echo held; fi >> "$PROBE"\n'
                'sleep 30 </dev/null >/dev/null 2>&1 &\n'
                'echo $! > "$LINGER_PID"\n'
            )
            editor.chmod(0o755)
            env = {key: value for key, value in os.environ.items()
                   if key not in {'HANDOFF_RETURN_FOCUS', 'TMUX_PANE'}}
            env.update(XDG_STATE_HOME=str(state), XDG_RUNTIME_DIR=str(base / 'runtime'),
                       HANDOFF_UUID=UUID, HANDOFF_ORIGIN='%7', HANDOFF_NVIM_COMMAND=str(editor),
                       HANDOFF_SAVE_SCRIPT=str(noop), HANDOFF_RECONCILE_COMMAND=str(noop),
                       PROBE=str(probe), LOCK=str(lock), LINGER_PID=str(linger_pid))
            # Output goes to a file: the lingering child keeps any pipe open.
            output = base / 'output'
            try:
                with open(output, 'w') as sink:
                    result = subprocess.run([str(EDITOR), str(base / 'brief.md')], env=env,
                                            stdout=sink, stderr=subprocess.STDOUT, timeout=10)
                self.assertEqual(result.returncode, 0, output.read_text())
                self.assertEqual(probe.read_text().split(), ['closed', 'held'])
                with open(lock) as handle:
                    try:
                        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    except BlockingIOError:
                        self.fail('a child the editor left behind still holds the brief lock')
            finally:
                if linger_pid.exists():
                    try:
                        os.kill(int(linger_pid.read_text()), signal.SIGTERM)
                    except ProcessLookupError:
                        pass


if __name__ == '__main__':
    unittest.main()
