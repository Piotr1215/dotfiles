"""Exercise real tmux 3.8 panes, Neovim RPC and inotify on a private server."""
import json
import contextlib
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time
import unittest
import warnings

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts/__handoff_floater.sh'
A = '11111111-1111-4111-8111-111111111111'
B = '22222222-2222-4222-8222-222222222222'


def private_processes(marker):
    """PIDs whose environment or command line names this test's private directory."""
    found = []
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        with contextlib.suppress(OSError):
            if marker in (proc / 'environ').read_bytes() or marker in (proc / 'cmdline').read_bytes():
                found.append(int(proc.name))
    return found


def self_expiring(wrapper, command):
    """Run the base pane so its exit stops the private server.

    A floating brief keeps a tmux server alive after the base pane ends, so a
    test process killed before teardown would otherwise orphan the server and
    its editor. The base command is bounded (sleep 120 or timeout 120).
    """
    return ['sh', '-c', '"$@"; exec "$0" kill-server', str(wrapper), *command]


def stop_private_server(test, wrapper, env, directory):
    """Stop the test's own tmux server and prove nothing it started survives.

    Killing only the session left the brief editor (Neovim, its watcher and
    inotifywait) holding the private server open for hours after a run.
    """
    def describe(pid):
        with contextlib.suppress(OSError):
            command = Path('/proc', str(pid), 'cmdline').read_bytes().replace(bytes(1), b' ')
            state = Path('/proc', str(pid), 'stat').read_text().rsplit(')', 1)[1].split()[:2]
            return f"{pid} state={state[0]} ppid={state[1]} {command.decode(errors='replace')}"
        return f'{pid} (gone)'

    panes = subprocess.run([str(wrapper), 'list-panes', '-a', '-F',
                            '#{pane_id} floating=#{pane_floating_flag} pid=#{pane_pid} #{pane_current_command}'],
                           env=env, capture_output=True, text=True, check=False).stdout.strip()
    before = private_processes(os.fsencode(directory))
    subprocess.run([str(wrapper), 'kill-server'], env=env, capture_output=True, check=False)
    marker = os.fsencode(directory)
    deadline = time.monotonic() + 10
    while (left := private_processes(marker)) and time.monotonic() < deadline:
        time.sleep(.1)
    # An editor can survive its pane's SIGHUP (seen with Neovim and its Copilot
    # LSP child). These carry this test's private directory, so they are the
    # test's own: name them, then stop them so no run leaves them behind.
    if left:
        warnings.warn('stopping processes that survived kill-server: '
                      + '; '.join(describe(pid) for pid in left), ResourceWarning)
        for signal_number, wait in ((signal.SIGTERM, 5), (signal.SIGKILL, 5)):
            for pid in left:
                with contextlib.suppress(OSError):
                    os.kill(pid, signal_number)
            deadline = time.monotonic() + wait
            while (left := private_processes(marker)) and time.monotonic() < deadline:
                time.sleep(.1)
            if not left:
                break
    test.assertEqual(left, [], 'processes from the private tmux server outlived teardown:\n'
                     + '\n'.join(describe(pid) for pid in left)
                     + f'\npanes before teardown:\n{panes}\nprocesses before teardown: {sorted(before)}')


@unittest.skipUnless(all(shutil.which(x) for x in ('tmux', 'nvim', 'inotifywait')), 'needs tmux, nvim, inotifywait')
class FloaterLiveTest(unittest.TestCase):
    def test_save_switch_reuse_and_hide(self):
        self.exercise()

    def test_peek_placement_tracks_selected_row(self):
        self.exercise(placement=True)

    @unittest.skipUnless(os.environ.get('HANDOFF_LIVE_TUI'), 'set HANDOFF_LIVE_TUI to the patched Twoy binary')
    def test_real_twoy_selection(self):
        self.exercise(real_twoy=True)

    def exercise(self, real_twoy=False, placement=False):
        with tempfile.TemporaryDirectory(prefix='floater-test-') as directory, contextlib.ExitStack() as cleanup:
            base = Path(directory)
            env = dict(os.environ, XDG_RUNTIME_DIR=directory, XDG_STATE_HOME=str(base / 'state'))
            tmux_socket = str(base / 'tmux.sock')
            wrapper = base / 'tmux'
            wrapper.write_text(f'#!/bin/sh\nexec {shutil.which("tmux")} -S "{tmux_socket}" "$@"\n')
            wrapper.chmod(0o700)
            fixture = base / 'tasks.json'
            fixture.write_text(json.dumps([{'uuid': u, 'description': 'Test ' + u, 'tags': ['piotr'],
                                           'annotations': [{'entry': '20261106T120000Z', 'description': 'brief: Fixture'}]}
                                          for u in (A, B)]))
            task = base / 'task'
            task.write_text(f'#!/bin/sh\ncat "{fixture}"\n')
            task.chmod(0o700)
            env.update(HANDOFF_TMUX_COMMAND=str(wrapper), HANDOFF_TASK_COMMAND=str(task))

            def tmux(*args):
                return subprocess.check_output([str(wrapper), *args], env=env, text=True).strip()

            # Teardown stops this private server; it never touches another one.
            command = ['sleep', '120']
            if real_twoy:
                rc = base / 'taskrc'
                rc.write_text(f'data.location={base / "tasks"}\nconfirmation=no\nhooks=off\n'
                              'report.signal.columns=id,description\nreport.signal.labels=ID,Description\n'
                              'report.signal.sort=id+\nreport.signal.filter=status:pending\n'
                              'uda.taskwarrior-tui.task-report.show-info=false\n')
                env.update(TASKRC=str(rc), TASKDATA=str(base / 'tasks'))
                subprocess.run(['task', 'import', '-'], env=env, text=True, check=True, capture_output=True,
                               input=json.dumps([{'uuid': u, 'description': u, 'status': 'pending',
                                                  'entry': '20260101T000000Z'} for u in (A, B)]))
                command = ['env', f'TASKRC={rc}', f'TASKDATA={base / "tasks"}',
                           f'XDG_RUNTIME_DIR={directory}', 'timeout', '--foreground', '120', os.environ['HANDOFF_LIVE_TUI'],
                           '--report', 'signal', '--data', str(base / 'tui')]
            origin = tmux('-f', '/dev/null', 'new-session', '-d', '-P', '-F', '#{pane_id}',
                          '-s', 'floater-test', '-x', '160', '-y', '50', *self_expiring(wrapper, command))
            cleanup.callback(stop_private_server, self, wrapper, env, directory)
            env['TMUX_PANE'] = origin
            runtime = base / 'taskwarrior-tui'
            socket = runtime / f'handoff-{origin[1:]}.sock'

            def rpc(expression):
                return subprocess.check_output(['nvim', '--server', str(socket), '--remote-expr', expression],
                                               env=env, text=True, stderr=subprocess.STDOUT, timeout=10).strip()

            def close_editor():
                if socket.exists():
                    with contextlib.suppress(subprocess.SubprocessError):
                        rpc("luaeval('HandoffHide()')")
            cleanup.callback(close_editor)

            def invoke(mode, uid=A, row=None):
                args = [str(SCRIPT), mode, uid, origin]
                if row is not None:
                    args.append(str(row))
                subprocess.run(args, env=env, check=True, capture_output=True, text=True)

            def until(predicate):
                deadline = time.monotonic() + 8
                while time.monotonic() < deadline:
                    if predicate():
                        return
                    time.sleep(.05)
                self.fail('condition did not become true')

            if placement:
                for row, expected_top in ((0, 2), (18, 20), (45, 19)):
                    invoke('toggle', A, row)
                    tops = tmux('list-panes', '-t', origin, '-F', '#{pane_floating_flag} #{pane_top}')
                    floating_top = [int(line.split()[1]) for line in tops.splitlines() if line.startswith('1 ')]
                    self.assertEqual(floating_top, [expected_top], f'row {row}: {tops}')
                    # b gives the brief keyboard focus at once.
                    self.assertEqual(sorted(tmux('list-panes', '-t', origin, '-F',
                                                 '#{pane_floating_flag} #{pane_active}').splitlines()), ['0 0', '1 1'])
                    invoke('toggle', A, row)
                    until(lambda: len(tmux('list-panes', '-t', origin, '-F', '#{pane_id}').splitlines()) == 1)
                    self.assertEqual(tmux('display-message', '-p', '-t', origin, '#{pane_active}'), '1')
                # Quitting Neovim inside the focused brief hands focus back to the task view,
                # even when another tiled pane was used more recently than the task view.
                other = tmux('split-window', '-d', '-P', '-F', '#{pane_id}', '-t', origin, 'cat')
                tmux('select-pane', '-t', other)
                tmux('select-pane', '-t', origin)
                invoke('toggle', A, 0)
                floating = next(line.split()[1] for line in tmux('list-panes', '-t', origin, '-F',
                                '#{pane_floating_flag} #{pane_id}').splitlines() if line.startswith('1 '))
                tmux('select-pane', '-t', other)
                tmux('select-pane', '-t', floating)
                tmux('send-keys', '-t', floating, 'Escape', ':qa', 'Enter')
                until(lambda: not socket.exists())
                until(lambda: floating not in tmux('list-panes', '-t', origin, '-F', '#{pane_id}'))
                self.assertEqual(tmux('display-message', '-p', '-t', origin, '#{pane_active}'), '1')
                tmux('send-keys', '-t', other, 'C-d')  # cat exits; no pane kill command
                until(lambda: other not in tmux('list-panes', '-t', origin, '-F', '#{pane_id}'))

            invoke('open')
            editor_pid = rpc('getpid()')
            # Full Neovim starts plugin children too; the watcher is the one to track.
            watcher_pid = subprocess.check_output(['pgrep', '-P', editor_pid, '-f', '__handoff_floater.sh watch'],
                                                  text=True).strip()
            self.assertTrue(watcher_pid.isdigit())
            panes = tmux('list-panes', '-t', origin, '-F', '#{pane_id} #{pane_floating_flag} #{pane_active}')
            self.assertIn(f'{origin} 0 1', panes)
            self.assertIn(' 1 0', panes)
            self.assertEqual(len(panes.splitlines()), 2)
            # The editor saves the current brief when the selection switches away from it.
            rpc("setline(1, 'Edited before selection change')")
            time.sleep(.15)  # Wait for the test's inotify subscriber startup.
            selected = runtime / f'selected-{origin[1:]}'
            temporary = runtime / 'selection.tmp'
            if real_twoy:
                until(lambda: selected.exists() and selected.read_text().split()[0] == A)
                tmux('send-keys', '-t', origin, 'j')
                until(lambda: selected.read_text().split()[0] == B)
            else:
                temporary.write_text(B + '\n')
                temporary.replace(selected)
            until(lambda: B in rpc("expand('%:p')"))
            if real_twoy:
                tmux('send-keys', '-t', origin, 'k')
                until(lambda: A in rpc("expand('%:p')"))
                tmux('send-keys', '-t', origin, 'j')
                until(lambda: B in rpc("expand('%:p')"))
            self.assertIn('Edited before selection change', (base / 'state/taskwarrior/briefs' / A / 'brief.md').read_text())
            self.assertEqual(panes, tmux('list-panes', '-t', origin, '-F', '#{pane_id} #{pane_floating_flag} #{pane_active}'))
            if real_twoy:
                invoke('close', B)
                until(lambda: len(tmux('list-panes', '-t', origin, '-F', '#{pane_id}').splitlines()) == 1)
                captured = subprocess.check_output([str(wrapper), 'capture-pane', '-p', '-t', origin],
                                                   env=env, text=True).splitlines()
                selected_y = next((i for i, line in enumerate(captured) if B in line), None)
                self.assertIsNotNone(selected_y, f'selected task UUID missing from TUI:\n{captured}')
                tmux('send-keys', '-t', origin, 'b')
                until(lambda: len(tmux('list-panes', '-t', origin, '-F', '#{pane_floating_flag}').splitlines()) == 2)
                pane = next(line.split() for line in
                            tmux('list-panes', '-t', origin, '-F', '#{pane_floating_flag} #{pane_top} #{pane_height}').splitlines()
                            if line.startswith('1 '))
                pane_top, pane_height = map(int, pane[1:])
                if selected_y + pane_height + 3 <= 50:
                    self.assertEqual(pane_top - 1, selected_y + 1,
                                     f'peek border should be below TUI row {selected_y}')
                else:
                    self.assertEqual(pane_top + pane_height, selected_y - 1,
                                     f'peek border should be above TUI row {selected_y}')
                tmux('send-keys', '-t', origin, 'b')
                until(lambda: len(tmux('list-panes', '-t', origin, '-F', '#{pane_id}').splitlines()) == 1)
            invoke('pin', A)
            pin_pane_top = int([line.split()[1] for line in
                                tmux('list-panes', '-t', origin, '-F', '#{pane_floating_flag} #{pane_top}').splitlines()
                                if line.startswith('1 ')][0])
            pin_pane_height = int([line.split()[1] for line in
                                   tmux('list-panes', '-t', origin, '-F', '#{pane_floating_flag} #{pane_height}').splitlines()
                                   if line.startswith('1 ')][0])
            temporary.write_text(B + '\n')
            temporary.replace(selected)
            time.sleep(.2)
            self.assertIn(A, rpc("expand('%:p')"))
            invoke('toggle', B, 18)
            peek_pane_top = int([line.split()[1] for line in
                                 tmux('list-panes', '-t', origin, '-F', '#{pane_floating_flag} #{pane_top}').splitlines()
                                 if line.startswith('1 ')][0])
            peek_pane_height = int([line.split()[1] for line in
                                    tmux('list-panes', '-t', origin, '-F', '#{pane_floating_flag} #{pane_height}').splitlines()
                                    if line.startswith('1 ')][0])
            self.assertEqual((peek_pane_top, peek_pane_height), (20, 25))
            self.assertIn(B, rpc("expand('%:p')"))
            invoke('toggle', B, 18)
            restored_pane_top = int([line.split()[1] for line in
                                     tmux('list-panes', '-t', origin, '-F', '#{pane_floating_flag} #{pane_top}').splitlines()
                                     if line.startswith('1 ')][0])
            restored_pane_height = int([line.split()[1] for line in
                                        tmux('list-panes', '-t', origin, '-F', '#{pane_floating_flag} #{pane_height}').splitlines()
                                        if line.startswith('1 ')][0])
            self.assertEqual((restored_pane_top, restored_pane_height), (pin_pane_top, pin_pane_height))
            self.assertIn(A, rpc("expand('%:p')"))
            invoke('close', A)
            until(lambda: len(tmux('list-panes', '-t', origin, '-F', '#{pane_id}').splitlines()) == 1)
            invoke('pin', A)
            pinned_id = (runtime / f'floater-{origin[1:]}').with_suffix('.id').read_text().strip()
            # Quit outside the floater script, which leaves its runtime markers behind.
            tmux('send-keys', '-t', pinned_id, 'Escape', ':qa', 'Enter')
            until(lambda: not socket.exists())
            self.assertTrue((runtime / f'pinned-{origin[1:]}').exists())
            invoke('toggle', B, 45)
            self.assertFalse((runtime / f'pinned-{origin[1:]}').exists())
            self.assertFalse((runtime / f'peeking-{origin[1:]}').exists())
            reopened_top = int([line.split()[1] for line in
                                tmux('list-panes', '-t', origin, '-F', '#{pane_floating_flag} #{pane_top}').splitlines()
                                if line.startswith('1 ')][0])
            self.assertEqual(reopened_top, 19)
            invoke('toggle', B, 45)
            until(lambda: len(tmux('list-panes', '-t', origin, '-F', '#{pane_id}').splitlines()) == 1)
            invoke('open', B)
            panes = tmux('list-panes', '-t', origin, '-F', '#{pane_id} #{pane_floating_flag} #{pane_active}')
            invoke('open', B)
            self.assertEqual(panes, tmux('list-panes', '-t', origin, '-F', '#{pane_id} #{pane_floating_flag} #{pane_active}'))
            rpc("setline(1, 'Saved on hide')")
            invoke('toggle', B)
            until(lambda: len(tmux('list-panes', '-t', origin, '-F', '#{pane_id}').splitlines()) == 1)
            self.assertIn('Saved on hide', (base / 'state/taskwarrior/briefs' / B / 'brief.md').read_text())
            temporary.write_text(A + '\n')
            temporary.replace(selected)
            time.sleep(.15)
            self.assertFalse(socket.exists())
            until(lambda: not Path('/proc', watcher_pid).exists())
            self.assertEqual(tmux('list-panes', '-t', origin, '-F', '#{pane_id}'), origin)


COMMENT_LUA = ("luaeval('(function(t) local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false) "
               "for i, l in ipairs(lines) do if l == \"## My comments\" then "
               "vim.api.nvim_buf_set_lines(0, i, i, false, {t}) return i end end return -1 end)(_A)', '%s')")
# Count follows, keeping each call's task and time so a failure shows its cause.
COUNT_LUA = ("luaeval('(function() local f = _G.HandoffSelectionOriginal or HandoffSelection "
             "_G.HandoffSelectionOriginal = f _G.FollowCalls = 0 _G.FollowLog = {} "
             "_G.HandoffSelection = function(u) _G.FollowCalls = _G.FollowCalls + 1 "
             "table.insert(_G.FollowLog, u:sub(1, 8) .. \" \" .. math.floor(vim.uv.hrtime() / 1e6)) return f(u) end "
             "return 0 end)()')")
FOLLOW_LOG = "luaeval('table.concat(FollowLog, \", \")')"


@unittest.skipUnless(all(shutil.which(x) for x in ('tmux', 'nvim', 'inotifywait')), 'needs tmux, nvim, inotifywait')
class FollowSelectionLiveTest(unittest.TestCase):
    """The open brief follows the list selection: placement, debounce, edits, focus, close."""

    @contextlib.contextmanager
    def harness(self, uuids, tui=None):
        with tempfile.TemporaryDirectory(prefix='follow-test-', ignore_cleanup_errors=True) as directory, contextlib.ExitStack() as cleanup:
            base = Path(directory)
            h = type('Harness', (), {})()
            h.base, h.runtime = base, base / 'taskwarrior-tui'
            env = dict(os.environ, XDG_RUNTIME_DIR=directory, XDG_STATE_HOME=str(base / 'state'))
            tmux_socket = str(base / 'tmux.sock')
            wrapper = base / 'tmux'
            wrapper.write_text(f'#!/bin/sh\nexec {shutil.which("tmux")} -S "{tmux_socket}" "$@"\n')
            fixture = base / 'tasks.json'
            fixture.write_text(json.dumps([{'uuid': u, 'description': 'Test ' + u, 'tags': ['piotr'],
                                           'annotations': [{'entry': '20261106T120000Z', 'description': 'brief: Fixture'}]}
                                          for u in uuids]))
            fakes = {'task': f'cat "{fixture}"',
                     'tw': f'printf "%s\\n" "$*" >> "{base}/tw.log"',
                     'snd': f'[ -e "{base}/snd.fail" ] && exit 1; printf "%s\\n" "$*" >> "{base}/snd.log"'}
            for name, body in fakes.items():
                (base / name).write_text(f'#!/bin/sh\n{body}\n')
            for path in (wrapper, base / 'task', base / 'tw', base / 'snd'):
                path.chmod(0o700)
            env.update(HANDOFF_TMUX_COMMAND=str(wrapper), HANDOFF_TASK_COMMAND=str(base / 'task'),
                       HANDOFF_TW_WRAPPER=str(base / 'tw'), HANDOFF_SND_COMMAND=str(base / 'snd'))
            h.env = env

            def tmux(*args):
                return subprocess.check_output([str(wrapper), *args], env=env, text=True).strip()
            h.tmux = tmux
            # Teardown stops this private server; it never touches another one.
            command = tui(base, env) if tui else ['sleep', '120']
            origin = tmux('-f', '/dev/null', 'new-session', '-d', '-P', '-F', '#{pane_id}',
                          '-s', 'follow-test', '-x', '160', '-y', '50', *self_expiring(wrapper, command))
            cleanup.callback(stop_private_server, self, wrapper, env, directory)
            env['TMUX_PANE'] = h.origin = origin
            h.socket = h.runtime / f'handoff-{origin[1:]}.sock'
            h.selected = h.runtime / f'selected-{origin[1:]}'

            def rpc(expression):
                return subprocess.check_output(['nvim', '--server', str(h.socket), '--remote-expr', expression],
                                               env=env, text=True, stderr=subprocess.STDOUT, timeout=10).strip()
            h.rpc = rpc

            def close_editor():
                if h.socket.exists():
                    with contextlib.suppress(subprocess.SubprocessError):
                        rpc("luaeval('HandoffHide()')")
            cleanup.callback(close_editor)

            def invoke(mode, uid, row=None):
                args = [str(SCRIPT), mode, uid, origin] + ([str(row)] if row is not None else [])
                subprocess.run(args, env=env, check=True, capture_output=True, text=True)
            h.invoke = invoke

            def until(predicate, timeout=8):
                deadline = time.monotonic() + timeout
                while time.monotonic() < deadline:
                    with contextlib.suppress(subprocess.SubprocessError, OSError):
                        if predicate():
                            return
                    time.sleep(.05)
                self.fail('condition did not become true')
            h.until = until

            def floater():
                rows = [line.split() for line in tmux('list-panes', '-t', origin, '-F',
                        '#{pane_floating_flag} #{pane_id} #{pane_top} #{pane_height} #{pane_active}').splitlines()]
                floating = [row[1:] for row in rows if row[0] == '1']
                if not floating:
                    return None
                pane_id, top, height, active = floating[0]
                return pane_id, int(top), int(height), active == '1'
            h.floater = floater

            def select(uid, row):
                temporary = h.runtime / '.selection-test.tmp'
                temporary.write_text(f'{uid} {row}\n')
                temporary.replace(h.selected)
            h.select = select
            h.showing = lambda uid: uid in rpc("expand('%:p')")
            h.active = lambda pane: tmux('display-message', '-p', '-t', pane, '#{pane_active}') == '1'
            h.brief = lambda uid: (base / 'state/taskwarrior/briefs' / uid / 'brief.md').read_text()
            h.pending = lambda uid: (base / 'state/taskwarrior/briefs' / uid / '.piotr-pending-save.json').exists()
            h.log = lambda name: (base / name).read_text() if (base / name).exists() else ''
            yield h

    def watcher_pid(self, h):
        h.until(lambda: h.rpc('1') == '1')  # The pane exists before Neovim listens.
        editor_pid = h.rpc('getpid()')
        h.until(lambda: subprocess.run(['pgrep', '-P', editor_pid, '-f', '__handoff_floater.sh watch'],
                                       capture_output=True).returncode == 0)
        time.sleep(.3)  # inotifywait subscribes after its process starts.
        return subprocess.check_output(['pgrep', '-P', editor_pid, '-f', '__handoff_floater.sh watch'],
                                       text=True).split()[0]

    def test_follow_places_debounces_and_keeps_edits(self):
        with self.harness((A, B)) as h:
            # b opens the brief focused under row 0.
            h.invoke('toggle', A, 0)
            pane_id, top, _, active = h.floater()
            self.assertEqual((top, active), (2, True))
            watcher = self.watcher_pid(h)

            # Tab in the brief hands the keyboard to the list and keeps the brief open.
            h.tmux('send-keys', '-t', pane_id, 'Escape', 'Tab')
            h.until(lambda: h.active(h.origin))
            self.assertEqual(h.floater()[0], pane_id)

            # Placement on switch: below the row, or above it near the bottom.
            h.select(B, 18)
            h.until(lambda: h.showing(B) and h.floater()[1:3] == (20, 25))
            h.select(A, 45)
            h.until(lambda: h.showing(A) and h.floater()[1] == 19)
            self.assertTrue(h.active(h.origin))

            # Debounce: a held key renames the selection per row; the brief follows once.
            h.rpc(COUNT_LUA)
            for index in range(1, 16):
                h.select(B if index % 2 else A, index)
                time.sleep(.01)
            h.until(lambda: h.showing(B) and h.floater()[1] == 17)
            time.sleep(.5)
            self.assertEqual(h.rpc("luaeval('FollowCalls')"), '1', h.rpc(FOLLOW_LOG))

            # An unsaved comment is saved and delivered before the brief switches away.
            self.assertGreater(int(h.rpc(COMMENT_LUA % 'Draft note')), 0)
            self.assertEqual(h.rpc('&modified'), '1')
            h.select(A, 0)
            h.until(lambda: h.showing(A) and h.floater()[1] == 2)
            self.assertIn('Draft note', h.brief(B))
            self.assertIn('Draft note', h.log('snd.log'))
            self.assertFalse(h.pending(B))

            # A save that cannot deliver keeps the brief on its task and its row.
            (h.base / 'snd.fail').touch()
            self.assertGreater(int(h.rpc(COMMENT_LUA % 'Second note')), 0)
            h.select(B, 18)
            h.until(lambda: h.pending(A))
            time.sleep(.5)
            self.assertTrue(h.showing(A))
            self.assertEqual(h.floater()[1], 2)
            self.assertIn('Second note', h.brief(A))
            (h.base / 'snd.fail').unlink()
            h.select(B, 18)
            h.until(lambda: h.showing(B) and h.floater()[1] == 20)
            self.assertIn('Second note', h.log('snd.log'))
            self.assertFalse(h.pending(A))

            # While the brief has the keyboard it stays put; Tab back catches up.
            h.invoke('focus', '')
            h.until(lambda: h.active(pane_id))
            h.select(A, 45)
            time.sleep(.6)
            self.assertTrue(h.showing(B))
            self.assertEqual(h.floater()[1], 20)
            h.tmux('send-keys', '-t', pane_id, 'Tab')
            h.until(lambda: h.active(h.origin) and h.showing(A) and h.floater()[1] == 19)

            # Closing stops following: no pane, no editor, no watcher.
            h.invoke('toggle', A, 45)
            h.until(lambda: h.floater() is None and not h.socket.exists())
            h.until(lambda: not Path('/proc', watcher).exists())
            h.select(B, 18)
            time.sleep(.5)
            self.assertIsNone(h.floater())
            # Tab from the list with no brief open does nothing.
            h.invoke('focus', B)
            self.assertIsNone(h.floater())
            self.assertTrue(h.active(h.origin))

    @unittest.skipUnless(os.environ.get('HANDOFF_LIVE_TUI'), 'set HANDOFF_LIVE_TUI to the patched Twoy binary')
    def test_real_twoy_follow(self):
        uuids = [f'{i:08x}-0000-4000-8000-{i:012x}' for i in range(1, 11)]

        def tui(base, env):
            rc = base / 'taskrc'
            rc.write_text(f'data.location={base / "tasks"}\nconfirmation=no\nhooks=off\n'
                          'report.signal.columns=id,description\nreport.signal.labels=ID,Description\n'
                          'report.signal.sort=id+\nreport.signal.filter=status:pending\n'
                          'uda.taskwarrior-tui.task-report.show-info=false\n')
            subprocess.run(['task', 'import', '-'], env=dict(env, TASKRC=str(rc), TASKDATA=str(base / 'tasks')),
                           text=True, check=True, capture_output=True,
                           input=json.dumps([{'uuid': u, 'description': u, 'status': 'pending',
                                              'entry': f'202601{i + 1:02d}T000000Z'} for i, u in enumerate(uuids)]))
            return ['env', f'TASKRC={rc}', f'TASKDATA={base / "tasks"}', f'XDG_RUNTIME_DIR={base}',
                    'timeout', '--foreground', '120', os.environ['HANDOFF_LIVE_TUI'], '--report', 'signal', '--data', str(base / 'tui')]

        with self.harness(uuids, tui) as h:
            def row_of(uid):
                captured = h.tmux('capture-pane', '-p', '-t', h.origin).splitlines()
                return next(i for i, line in enumerate(captured) if uid in line)

            def under(uid):
                found = h.floater()
                return found is not None and found[1] - 1 == row_of(uid) + 1

            h.until(lambda: h.selected.read_text().split() == [uuids[0], str(row_of(uuids[0]))])
            # b opens the brief under the selected row with the keyboard.
            h.tmux('send-keys', '-t', h.origin, 'b')
            h.until(lambda: h.floater() is not None and h.floater()[3] and under(uuids[0]))
            pane_id = h.floater()[0]
            watcher = self.watcher_pid(h)
            # Tab in the brief returns the keyboard to the list.
            h.tmux('send-keys', '-t', pane_id, 'Escape', 'Tab')
            h.until(lambda: h.active(h.origin))

            h.rpc(COUNT_LUA)
            h.tmux('send-keys', '-t', h.origin, 'j')
            h.until(lambda: h.showing(uuids[1]) and under(uuids[1]))
            # Five j presses in one burst cost one follow.
            h.rpc(COUNT_LUA)
            h.tmux('send-keys', '-t', h.origin, 'j', 'j', 'j', 'j', 'j')
            h.until(lambda: h.showing(uuids[6]) and under(uuids[6]))
            time.sleep(.5)
            self.assertEqual(h.rpc("luaeval('FollowCalls')"), '1', h.rpc(FOLLOW_LOG))
            self.assertTrue(h.active(h.origin))

            # Tab in the list gives the brief the keyboard; Tab there gives it back.
            h.tmux('send-keys', '-t', h.origin, 'Tab')
            h.until(lambda: h.active(pane_id))
            h.tmux('send-keys', '-t', pane_id, 'Tab')
            h.until(lambda: h.active(h.origin))

            # b closes the brief and following stops.
            h.tmux('send-keys', '-t', h.origin, 'b')
            h.until(lambda: h.floater() is None and not h.socket.exists())
            h.until(lambda: not Path('/proc', watcher).exists())
            h.tmux('send-keys', '-t', h.origin, 'k')
            h.until(lambda: h.selected.read_text().split()[0] == uuids[5])
            time.sleep(.5)
            self.assertIsNone(h.floater())


if __name__ == '__main__':
    unittest.main()
