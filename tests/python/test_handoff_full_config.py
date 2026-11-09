import json, os, subprocess, time
from pathlib import Path

def test_open(tmp_path):
    uid='11111111-1111-4111-8111-111111111111'
    task=tmp_path/'task'; task.write_text('#!/bin/sh\necho ' + "'" + json.dumps([{'uuid':uid,'description':'fixture','annotations':[]}]) + "'\n"); task.chmod(0o755)
    nvim=tmp_path/'nvim'; nvim.write_text('#!/bin/sh\nexec /usr/local/bin/nvim --headless "$@"\n'); nvim.chmod(0o755)
    tmux=tmp_path/'tmux'; tmux.write_text('''#!/usr/bin/env python3
import subprocess,sys
if sys.argv[1] == 'new-pane':
 i=sys.argv.index('env'); subprocess.Popen(sys.argv[i:],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True); print('%2')
else: sys.exit(1)
'''); tmux.chmod(0o755)
    env=dict(os.environ, XDG_STATE_HOME=str(tmp_path/'state'), XDG_RUNTIME_DIR=str(tmp_path/'runtime'), HANDOFF_TASK_COMMAND=str(task), HANDOFF_NVIM_COMMAND=str(nvim), HANDOFF_TMUX_COMMAND=str(tmux))
    result=subprocess.run([str(Path(__file__).resolve().parents[2]/'scripts/__handoff_floater.sh'),'open',uid,'%1'],env=env,text=True,capture_output=True,timeout=15)
    assert result.returncode == 0, result.stderr
    socket=tmp_path/'runtime/taskwarrior-tui/handoff-1.sock'
    answer=subprocess.run([str(nvim),'--server',str(socket),'--remote-expr',"expand('%:p')"],env=env,text=True,capture_output=True,timeout=5)
    assert uid in answer.stdout, answer.stderr
    config=subprocess.run([str(nvim),'--server',str(socket),'--remote-expr','stdpath("config")'],env=env,text=True,capture_output=True,timeout=5,check=True)
    assert config.stdout.strip() == str(Path.home()/'.config/nvim')
    loaded=subprocess.run([str(nvim),'--server',str(socket),'--remote-expr',"luaeval('package.loaded.plugins ~= nil')"],env=env,text=True,capture_output=True,timeout=5,check=True)
    assert loaded.stdout.strip() == 'true'
    mapping=subprocess.run([str(nvim),'--server',str(socket),'--remote-expr','maparg("q", "n")'],env=env,text=True,capture_output=True,timeout=5,check=True)
    assert 'HandoffHide' not in mapping.stdout
    subprocess.run([str(nvim),'--server',str(socket),'--remote-expr',"luaeval('HandoffHide()')"],env=env,text=True,capture_output=True,timeout=5,check=True)
