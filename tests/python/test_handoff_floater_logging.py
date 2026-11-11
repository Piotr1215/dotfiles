import ctypes
import ctypes.util
import json
import os
from pathlib import Path
import subprocess

import pytest

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/__handoff_floater.sh'


def test_invalid_selection_is_logged_with_uuid_and_timestamp(tmp_path):
    env = dict(os.environ, HOME=str(tmp_path), XDG_STATE_HOME=str(tmp_path), XDG_RUNTIME_DIR=str(tmp_path))
    result = subprocess.run([str(SCRIPT), 'open', 'invalid', '%1'], env=env, capture_output=True, text=True)
    assert result.returncode == 2
    log = (tmp_path / 'handoff-floater.log').read_text()
    assert 'uuid=invalid mode=open Select a task with a full UUID' in log
    assert log[:4].isdigit()


A = '12345678-1234-1234-1234-123456789abc'
B = '87654321-4321-4321-4321-cba987654321'


@pytest.fixture
def floater(tmp_path):
    """All terminal/editor/task commands are local fakes, including socket readiness."""
    bindir = tmp_path / 'bin'
    bindir.mkdir()
    fake = bindir / 'fake-command'
    fake.write_text('''#!/usr/bin/env python3
import json, os, pathlib, re, socket, sys, time
base = pathlib.Path(os.environ['FAKE_ROOT'])
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with (base / 'calls.jsonl').open('a') as stream:
    stream.write(json.dumps([name, args]) + '\\n')
runtime = base / 'runtime/taskwarrior-tui'
sock = runtime / 'handoff-7.sock'
if name == 'task':
    print((base / 'export.json').read_text())
elif name == 'tmux':
    if args[0] == 'new-pane':
        sock.unlink(missing_ok=True)
        connection = socket.socket(socket.AF_UNIX)
        connection.bind(str(sock))
        connection.close()
        uid = next(arg.split('=', 1)[1] for arg in args if arg.startswith('HANDOFF_UUID='))
        (base / 'current').write_text(uid)
        print('%99')
    elif args[0] == 'display-message':
        values = {'#{window_width} #{window_height}': os.environ.get('FAKE_DIMENSIONS', '160 50'),
                  '#{pane_top} #{window_height}': '0 50', '#{pane_active}': '0',
                  '#{pane_left}': '9', '#{pane_left} #{pane_top}': '9 12',
                  '#{pane_width} #{pane_height}': '90 30'}
        print(values[args[-1]])
elif name == 'nvim':
    expression = args[-1]
    if expression == '1': print('1')
    elif 'HandoffCurrent' in expression: print((base / 'current').read_text())
    elif 'vim.env.TMUX_PANE' in expression: print('%99')
    elif 'HandoffHide' in expression:
        sock.unlink(missing_ok=True)
        print('1')
    else:
        matches = re.findall(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}", expression)
        if matches: (base / 'current').write_text(matches[-1])
        print('1')
elif name == 'inotifywait':
    print('selected-7', flush=True)
    time.sleep(.1)
''')
    fake.chmod(0o755)
    for name in ('tmux', 'nvim', 'task', 'inotifywait'):
        (bindir / name).symlink_to(fake)
    (tmp_path / 'export.json').write_text(json.dumps([
        {'uuid': uid, 'description': 'Project', 'tags': ['view'], 'view_key': 'standing:example',
         'annotations': [{'entry': '20261111T100000Z', 'description': 'brief: # Context'}]}
        for uid in (A, B)]))
    env = dict(os.environ, HOME=str(tmp_path), XDG_CONFIG_HOME=str(tmp_path / 'config'),
               XDG_STATE_HOME=str(tmp_path / 'state'), XDG_RUNTIME_DIR=str(tmp_path / 'runtime'),
               FAKE_ROOT=str(tmp_path), HANDOFF_TMUX_COMMAND=str(bindir / 'tmux'),
               HANDOFF_NVIM_COMMAND=str(bindir / 'nvim'), HANDOFF_TASK_COMMAND=str(bindir / 'task'),
               PATH=str(bindir) + os.pathsep + os.environ['PATH'], TMUX_PANE='%7')
    runtime = tmp_path / 'runtime/taskwarrior-tui'

    class FakeFloater:
        def __init__(self):
            self.env = env
            self.runtime = runtime
            self.base = tmp_path

        def invoke(self, mode='toggle', uid=A, tail=(), pane='%7'):
            args = [str(SCRIPT), mode, uid]
            if pane is not None:
                args.append(pane)
            return subprocess.run([*args, *map(str, tail)], env=env,
                                  capture_output=True, text=True, timeout=10)

        def calls(self, name):
            log = tmp_path / 'calls.jsonl'
            rows = [json.loads(row) for row in log.read_text().splitlines()] if log.exists() else []
            return [args for command, args in rows if command == name]

    return FakeFloater()


@pytest.mark.parametrize('tail', [(), ('2',), ('--layout', 'project'),
                                 ('2', '--layout', 'project'), ('--layout', 'default')])
def test_positional_and_appended_layout_forms(floater, tail):
    result = floater.invoke(tail=tail)
    assert result.returncode == 0, result.stderr
    calls = floater.calls('tmux')
    launch = next(args for args in calls if args[0] == 'new-pane')
    assert '-d' not in launch
    assert len([args for args in calls if args[0] == 'new-pane']) == 1


def test_original_implicit_source_pane_and_focus_without_uuid(floater):
    result = floater.invoke(pane=None)
    assert result.returncode == 0, result.stderr
    result = floater.invoke(mode='focus', uid='')
    assert result.returncode == 0, result.stderr
    assert ['select-pane', '-t', '%99'] in floater.calls('tmux')


def test_layout_flag_with_implicit_source_pane(floater):
    result = floater.invoke(pane=None, tail=('--layout', 'project'))
    assert result.returncode == 0, result.stderr
    assert (floater.runtime / 'layout-7').read_text() == 'project\n'


@pytest.mark.parametrize('tail', [('--layout',), ('--layout', 'unknown'),
                                 ('2', '3'), ('--layout', 'project', '2')])
def test_bad_arguments_do_not_launch_editor(floater, tail):
    assert floater.invoke(tail=tail).returncode == 2
    assert floater.calls('tmux') == []


@pytest.mark.parametrize('dimensions', [(200, 60), (160, 50), (80, 24), (40, 10), (10, 5), (3, 3)])
def test_project_geometry_stays_inside_window_and_leaves_list(floater, dimensions):
    width, height = dimensions
    floater.env['FAKE_DIMENSIONS'] = f'{width} {height}'
    result = floater.invoke(tail=('48', '--layout', 'project'))
    assert result.returncode == 0, result.stderr
    launch = next(args for args in floater.calls('tmux') if args[0] == 'new-pane')
    fw, fh, left, top = [int(launch[launch.index(flag) + 1]) for flag in ('-x', '-y', '-X', '-Y')]
    assert 3 <= fw <= width and 3 <= fh <= height
    assert left >= 0 and top >= 0 and left + fw == width and top + fh <= height
    assert fh >= height - 2
    if width >= 80:
        assert left >= 40


def test_impossibly_small_terminal_fails_without_creating_pane(floater):
    floater.env['FAKE_DIMENSIONS'] = '2 2'
    result = floater.invoke(tail=('--layout', 'project'))
    assert result.returncode == 1
    assert 'too small' in result.stderr
    assert not any(args[0] == 'new-pane' for args in floater.calls('tmux'))


def test_project_b_replaces_child_in_same_window_then_same_uuid_closes(floater):
    assert floater.invoke(tail=('--layout', 'project')).returncode == 0
    result = floater.invoke(uid=B, tail=('45', '--layout', 'project'))
    assert result.returncode == 0, result.stderr
    calls = floater.calls('tmux')
    assert len([args for args in calls if args[0] == 'new-pane']) == 1
    assert not any(args[0] in ('move-pane', 'resize-pane') for args in calls)
    assert any('HandoffSwitch' in args[-1] and B in args[-1] for args in floater.calls('nvim'))
    assert not any('HandoffHide' in args[-1] for args in floater.calls('nvim'))
    assert (floater.base / 'current').read_text() == B
    assert floater.invoke(uid=B, tail=('--layout', 'project')).returncode == 0
    assert any('HandoffHide' in args[-1] for args in floater.calls('nvim'))
    assert not (floater.runtime / 'layout-7').exists()


@pytest.mark.parametrize('mode', ['focus', 'focus-list', 'watch'])
def test_project_selection_never_switches_or_moves(floater, mode):
    assert floater.invoke(tail=('--layout', 'project')).returncode == 0
    (floater.runtime / 'selected-7').write_text(B + ' 43\n')
    result = floater.invoke(mode=mode)
    assert result.returncode == 0, result.stderr
    assert not any('HandoffSelection' in args[-1] for args in floater.calls('nvim'))
    assert not any(args[0] in ('resize-pane', 'move-pane') for args in floater.calls('tmux'))
    assert (floater.base / 'current').read_text() == A
    assert (floater.runtime / 'layout-7').read_text() == 'project\n'


@pytest.mark.parametrize('tail', [(), ('--layout', 'default')])
def test_reusing_project_pane_with_default_open_restores_selection_follow(floater, tail):
    assert floater.invoke(mode='open', tail=('--layout', 'project')).returncode == 0
    result = floater.invoke(mode='open', uid=B, tail=tail)
    assert result.returncode == 0, result.stderr
    assert not (floater.runtime / 'layout-7').exists()
    assert len([args for args in floater.calls('tmux') if args[0] == 'new-pane']) == 1
    (floater.runtime / 'selected-7').write_text(A + ' 18\n')
    result = floater.invoke(mode='focus-list')
    assert result.returncode == 0, result.stderr
    assert any('HandoffSelection' in args[-1] and A in args[-1] for args in floater.calls('nvim'))
    assert any(args[0] == 'resize-pane' for args in floater.calls('tmux'))
    assert (floater.base / 'current').read_text() == A


def test_default_selection_follow_and_geometry_remain(floater):
    assert floater.invoke(tail=('0',)).returncode == 0
    launch = next(args for args in floater.calls('tmux') if args[0] == 'new-pane')
    assert launch[launch.index('-x') + 1] == '90%'
    assert launch[launch.index('-y') + 1] == '27'
    assert launch[launch.index('-Y') + 1] == '1'
    (floater.runtime / 'selected-7').write_text(B + ' 45\n')
    result = floater.invoke(mode='focus-list')
    assert result.returncode == 0, result.stderr
    assert any('HandoffSelection' in args[-1] for args in floater.calls('nvim'))
    assert any(args[0] == 'resize-pane' for args in floater.calls('tmux'))


def test_entering_project_layout_reuses_existing_window(floater):
    assert floater.invoke().returncode == 0
    result = floater.invoke(uid=B, tail=('--layout', 'project'))
    assert result.returncode == 0, result.stderr
    calls = floater.calls('tmux')
    assert len([args for args in calls if args[0] == 'new-pane']) == 1
    assert len([args for args in calls if args[0] == 'resize-pane']) == 1


@pytest.mark.parametrize('generated', [False, True])
def test_editor_wrapper_keeps_generated_context_out_of_handoff_init(floater, generated):
    root = floater.base
    uid_dir = root / 'state/taskwarrior/briefs' / A
    uid_dir.mkdir(parents=True)
    brief = uid_dir / ('project-status.md' if generated else 'brief.md')
    brief.write_text('# Context\n')
    logger = root / 'save.py'
    logger.write_text('import os, pathlib, sys\n'
                      'with (pathlib.Path(os.environ["FAKE_ROOT"]) / "save.log").open("a") as log:\n'
                      ' log.write(" ".join(sys.argv[1:]) + "\\n")\n')
    env = dict(floater.env, HANDOFF_SAVE_SCRIPT=str(logger), HANDOFF_RECONCILE_COMMAND=str(logger),
               HANDOFF_UUID=A, HANDOFF_ORIGIN='%7', HANDOFF_ROOT=str(SCRIPT.parent))
    result = subprocess.run([str(SCRIPT.with_name('__handoff_editor.sh')), str(brief)],
                            env=env, capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stderr
    saved = (root / 'save.log').read_text()
    assert (f'init {A}' in saved) is not generated
    assert '--reconcile-pending' in saved


def run_lua(source):
    """Execute the editor module against fake vim, with no real Neovim process."""
    library = ctypes.util.find_library('lua5.4') or ctypes.util.find_library('lua5.3')
    if not library:
        pytest.skip('fake editor tests need liblua5.4 or liblua5.3')
    lua = ctypes.CDLL(library)
    lua.luaL_newstate.restype = ctypes.c_void_p
    lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
    lua.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    lua.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int,
                             ctypes.c_int, ctypes.c_ssize_t, ctypes.c_void_p]
    lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
    lua.lua_tolstring.restype = ctypes.c_char_p
    lua.lua_close.argtypes = [ctypes.c_void_p]
    state = lua.luaL_newstate()
    try:
        lua.luaL_openlibs(state)
        result = lua.luaL_loadstring(state, source.encode())
        if result == 0:
            result = lua.lua_pcallk(state, 0, 0, 0, 0, None)
        assert result == 0, lua.lua_tolstring(state, -1, None).decode()
    finally:
        lua.lua_close(state)


FAKE_VIM = r'''
local A = "12345678-1234-1234-1234-123456789abc"
local B = "87654321-4321-4321-4321-cba987654321"
local folder = "/isolated/taskwarrior/briefs/"
local paths = { [A] = folder .. A .. "/" .. INITIAL_FILE, [B] = folder .. B .. "/brief.md" }
local buffers = {
  [1] = {name=paths[A], lines={"# Context"}, modified=false, modifiable=true},
  [2] = {name=paths[B], lines={"# Action"}, modified=false, modifiable=true}
}
local active = 1
local calls, callbacks, deferred, timer, mapped = {}, {}, {}, {}, {}
local checks, stopped, closed, quit = 0, false, false, false
local function buffer(id) return buffers[id == 0 and active or id] end
vim = {
 env = {HANDOFF_UUID=A, HANDOFF_ROOT="/source", HANDOFF_SAVE_SCRIPT="/fake-save.py",
        HANDOFF_ORIGIN="%7", HANDOFF_PINNED="0"},
 api={}, fn={}, keymap={}, uv={}, log={levels={ERROR=1}},
 bo=setmetatable({}, {__index=function(_, id) return buffer(id) end}),
 wo=setmetatable({}, {__index=function(t, id) local value={} rawset(t, id, value) return value end}),
 schedule=function(fn) fn() end, schedule_wrap=function(fn) return fn end,
 trim=function(text) return text:match("^%s*(.-)%s*$") end,
 notify=function(message) error(message) end,
 defer_fn=function(fn, delay) table.insert(deferred, {fn=fn, delay=delay}) end,
}
vim.api.nvim_buf_get_name = function(id) return buffer(id).name end
vim.api.nvim_get_current_buf = function() return active end
vim.api.nvim_buf_is_valid = function(id) return buffer(id) ~= nil end
vim.api.nvim_buf_get_lines = function(id) return buffer(id).lines end
vim.api.nvim_buf_set_lines = function(id, first, last, _, lines)
  local buf=buffer(id)
  assert(buf.modifiable, "Attempted to modify generated context")
  if last < 0 then last=#buf.lines end
  for index=last, first+1, -1 do table.remove(buf.lines,index) end
  for index,line in ipairs(lines) do table.insert(buf.lines, first+index, line) end
end
vim.api.nvim_create_autocmd = function(events, options)
  if type(events) == "string" then callbacks[events]=options.callback
  else for _,event in ipairs(events) do callbacks[event]=options.callback end end
end
vim.api.nvim_buf_call = function(_, fn) fn() end
vim.fn.fnamemodify = function(path, mode)
  return mode == ":h" and path:match("^(.*)/[^/]+$") or path
end
vim.fn.fnameescape = function(path) return path end
vim.fn.bufwinid = function() return 1 end
vim.fn.filereadable = function() return 0 end
vim.fn.jobstart = function(args) table.insert(calls, args) return 7 end
vim.fn.jobstop = function(job) assert(job == 7) end
vim.keymap.set = function(_, key, fn) mapped[key]=fn end
vim.system = function(args)
  table.insert(calls,args)
  local output = args[2] == "prepare" and paths[args[3]] or ""
  return {wait=function() return {code=0, stdout=output, stderr=""} end}
end
vim.cmd = setmetatable({edit=function(path)
  for id,buf in ipairs(buffers) do if buf.name == path then active=id end end
  if callbacks.BufEnter then callbacks.BufEnter({buf=active,event="BufEnter"}) end
end}, {__call=function(_, command)
  if command:find("checktime") then checks=checks+1 end
  if command == "qa" then quit=true end
end})
vim.uv.new_timer = function() return timer end
timer.start = function(_, first, interval, fn)
  assert(first == 1000 and interval == 1000)
  timer.tick=fn
end
timer.stop = function() stopped=true end
timer.close = function() closed=true end
local function count(verb, uid)
  local total=0
  for _,args in ipairs(calls) do
    if args[1] == "python3" and args[3] == verb and args[4] == uid then total=total+1 end
  end
  return total
end
'''


def test_generated_editor_reload_switch_and_close_use_fake_vim(floater):
    source = 'local INITIAL_FILE="project-status.md"\n' + FAKE_VIM
    source += '\ndofile(' + json.dumps(str(SCRIPT.with_name('__handoff_floater_v2.lua'))) + ')\n'
    source += r'''
assert(HandoffCurrent() == A)
assert(buffers[1].readonly and not buffers[1].modifiable and buffers[1].autoread)
assert(#buffers[1].lines == 1)
assert(count("init", A) == 0 and count("save", A) == 0)
assert(mapped["<Tab>"] ~= nil)
local before=#calls
local before_checks=checks
timer.tick()
assert(checks == before_checks+1 and #calls == before, "Reload must not poll tasks or source APIs")
assert(HandoffSwitch(B, true))
assert(not buffers[2].readonly and buffers[2].modifiable)
assert(count("init", B) == 1 and count("save", B) == 1)
assert(buffers[2].lines[3] == "## My comments")
local previous_checks=checks
timer.tick()
assert(checks == previous_checks, "Editable action buffers must not be reloaded by the timer")
assert(HandoffSwitch(A, true))
assert(buffers[1].readonly and not buffers[1].modifiable)
assert(count("init", A) == 0 and count("save", A) == 0)
timer.tick()
assert(checks > previous_checks)
assert(HandoffHide())
assert(not quit and deferred[1].delay == 100)
deferred[1].fn()
assert(quit)
callbacks.VimLeavePre()
assert(stopped and closed)
'''
    run_lua(source)


def test_default_editor_keeps_selection_pin_and_comments_with_fake_vim(floater):
    source = 'local INITIAL_FILE="brief.md"\n' + FAKE_VIM
    source += '\ndofile(' + json.dumps(str(SCRIPT.with_name('__handoff_floater_v2.lua'))) + ')\n'
    source += r'''
assert(not buffers[1].readonly and buffers[1].modifiable)
assert(buffers[1].lines[3] == "## My comments")
assert(count("save", A) == 1)
assert(HandoffSelection(B) == 1 and HandoffCurrent() == B)
assert(HandoffPin(B))
assert(HandoffSelection(A) == 0 and HandoffCurrent() == B)
assert(HandoffToggle(A) and HandoffCurrent() == A)
assert(HandoffToggle(A) and HandoffCurrent() == B)
assert(HandoffHide())
assert(not quit)
deferred[1].fn()
assert(quit)
callbacks.VimLeavePre()
'''
    run_lua(source)
