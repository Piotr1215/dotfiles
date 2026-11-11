"""Run the real Taskwarrior start hook and detached navigator in temp data."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

import pytest


TASK = "/usr/local/bin/task"
HOOK = Path.home() / ".task/hooks/on-modify-openurl-or-program.py"
SCRIPTS = Path(__file__).resolve().parents[2] / "scripts"


@pytest.mark.parametrize("command_only", [False, True])
def test_real_start_hook_keeps_newest_handoff_and_opens_reply_permalink(command_only):
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        data = root / "data"
        data.mkdir()
        hooks = data / "hooks"
        hooks.mkdir()
        (hooks / "on-modify-openurl-or-program.py").write_bytes(HOOK.read_bytes())
        (hooks / "on-modify-openurl-or-program.py").chmod(0o755)
        home = root / "home"
        (home / "dev/dotfiles/scripts").mkdir(parents=True)
        (home / ".task").symlink_to(data, target_is_directory=True)
        scripts = home / "dev/dotfiles/scripts"
        for script in ("__handoff_navigate.sh", "__handoff_navigate.py", "__handoff_floater_file.py", "__slack_open.sh"):
            (scripts / script).write_bytes((SCRIPTS / script).read_bytes())
            (scripts / script).chmod(0o755)
        bin_dir = root / "bin"
        bin_dir.mkdir()
        xdg_open = bin_dir / "xdg-open"
        xdg_open.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "with open(os.environ['MOCK_LOG'], 'a') as f: "
            "f.write(json.dumps(sys.argv[1:])+'\\n')\n"
        )
        xdg_open.chmod(0o755)
        helper_dir = home / ".claude/scripts"
        helper_dir.mkdir(parents=True)
        (helper_dir / "__tw_brief.py").write_bytes((Path.home() / ".claude/scripts/__tw_brief.py").read_bytes())
        taskrc = root / "taskrc"
        taskrc.write_text(
            f"data.location={data}\n"
            f"hooks.location={hooks}\n"
            "verbose=nothing\n"
            "hooks=on\n"
            "confirmation=no\n"
        )
        (home / ".taskrc").symlink_to(taskrc)
        runtime = root / "runtime"
        state = root / "state"
        log = root / "calls.jsonl"
        brief = root / "brief.md"
        brief.write_text(
            "<!-- begin open -->\n"
            "https://loft-labs-inc.slack.com/archives/C07G0T9HS4U/"
            "p1793971823896409?thread_ts=1793868031.988299&cid=C07G0T9HS4U\n"
            "<!-- end open -->\n"
        )
        mock = root / "mock-ui"
        mock.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "with open(os.environ['MOCK_LOG'], 'a') as f: f.write(json.dumps(sys.argv[1:])+'\\n')\n"
            "if sys.argv[1] == 'prepare': os.execv(sys.executable, [sys.executable, os.environ['PREPARE_SCRIPT'], sys.argv[2]])\n"
        )
        mock.chmod(0o755)
        tmux = root / "tmux"
        tmux.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "args = sys.argv[1:]\n"
            "with open(os.environ['MOCK_LOG'], 'a') as f: f.write(json.dumps(args)+'\\n')\n"
            "if args[0] == 'display-message': print('$9')\n"
            "if args[0] == 'new-window':\n"
            "    if args[args.index('-t') + 1] != '$9:':\n"
            "        print('index in use', file=sys.stderr); sys.exit(1)\n"
            "    print('%99')\n"
        )
        tmux.chmod(0o755)
        task_bin = root / "task"
        task_bin.symlink_to(TASK)
        env = dict(os.environ)
        env.pop("PYTEST_CURRENT_TEST", None)
        env.pop("BATS_TEST_FILENAME", None)
        env.update(HOME=str(home), TASKRC=str(taskrc), TASKDATA=str(data),
                   XDG_RUNTIME_DIR=str(runtime), XDG_STATE_HOME=str(state),
                   PATH=str(bin_dir) + os.pathsep + os.environ["PATH"], SLACK_TEAM_ID="TTEST", SLACK_OPEN_NO_DETACH="1",
                   HANDOFF_TASK_COMMAND=str(task_bin), HANDOFF_FLOATER_COMMAND=str(mock),
                   HANDOFF_LAYOUT_COMMAND=str(mock), HANDOFF_BROWSER_COMMAND=str(mock),
                   HANDOFF_TMUX_COMMAND=str(tmux), MOCK_LOG=str(log), PREPARE_SCRIPT=str(scripts / "__handoff_floater_file.py"), TMUX_PANE="%77")

        def task(*args):
            return subprocess.run([TASK, *args], env=env, capture_output=True, text=True,
                                  check=True, timeout=10)

        ids = []
        for desc, tags in (("first", "piotr"), ("second", "piotr"),
                           ("third", "piotr"), ("ordinary", "work")):
            task("add", "description:" + desc, "+" + tags)
            matches = json.loads(task("rc.context=none", "rc.hooks=off", "description:" + desc,
                                      "export").stdout)
            ids.append(matches[0]["uuid"])
        permalink = "https://loft-labs-inc.slack.com/archives/C07G0T9HS4U/p1793971823896409?thread_ts=1793868031.988299&cid=C07G0T9HS4U"
        if command_only:
            task("rc.hooks=off", ids[2], "annotate", "--", "cmd: echo safe && echo ready")
        else:
            task("rc.hooks=off", ids[2], "annotate", "--", "target: slack:C07G0T9HS4U/1793868031.988299 " + permalink)
        ordinary = ids[-1]
        task("rc.hooks=off", ordinary, "start")
        for uid in ids[:3]:
            task(uid, "start")
            time.sleep(1.05)

        deadline = time.monotonic() + 8
        active = []
        while time.monotonic() < deadline:
            exported = json.loads(task("rc.context=none", "rc.hooks=off", "+piotr",
                                       "+ACTIVE", "export").stdout)
            active = [row["uuid"] for row in exported]
            if len(active) == 1:
                break
            time.sleep(0.05)
        assert len(active) == 1, f"active +piotr UUIDs: {active}"
        winner = active[0]
        assert winner == ids[2]
        still_active = json.loads(task("rc.context=none", "rc.hooks=off", ordinary,
                                       "+ACTIVE", "export").stdout)
        assert [row["uuid"] for row in still_active] == [ordinary]

        deadline = time.monotonic() + 8
        calls = []
        while time.monotonic() < deadline:
            if log.exists():
                calls = [json.loads(line) for line in log.read_text().splitlines()]
                if (["send-keys", "-t", "%99", "Enter"] in calls if command_only
                        else any(call and call[0].startswith("slack://") for call in calls)):
                    break
            time.sleep(0.05)
        assert ["prepare", winner, "%77"] in calls
        if command_only:
            new = next(call for call in calls if call[0] == "new-window")
            assert new[new.index("-t") + 1] == "$9:"
            assert "HANDOFF_CMD=echo safe && echo ready" in new
            assert ["send-keys", "-t", "%99", "Enter"] in calls
        else:
            assert ["slack://channel?team=TTEST&id=C07G0T9HS4U&message=1793971823.896409&thread_ts=1793868031.988299"] in calls, calls
