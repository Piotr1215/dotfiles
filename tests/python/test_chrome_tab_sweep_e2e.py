"""Load Tab sweep into headless Chrome and sweep real tabs through the real host.

gh and snd are fakes (see test_chrome_tab_sweep.py), so nothing reaches
GitHub or the agents bus."""
import json
import os
import select
import shutil
import signal
import subprocess
import time
import urllib.request
import uuid
from pathlib import Path

import pytest

from test_chrome_agent_tmux_e2e import CDP, extension_id
from test_chrome_tab_sweep import FAKE_GH, FAKE_SND, map_tabs, script

ROOT = Path(__file__).resolve().parents[2]
CHROME = os.environ.get("AGENT_TAB_TEST_CHROME") or shutil.which("google-chrome")
EXTENSION = ROOT / ".config/chrome-tab-sweep"
HOST = ROOT / "scripts/__chrome_tab_sweep.py"
EXTENSION_ID = extension_id(json.loads((EXTENSION / "manifest.json").read_text())["key"])
PR = "https://github.com/o/r/pull"


@pytest.fixture
def chrome(tmp_path, request):
    """Headless Chrome with the extension loaded; yields (cdp, port, worker session, tmp_path)."""
    home, profile = tmp_path / "home", tmp_path / "profile"
    manifest = {"name": "org.piotr.tab_sweep", "description": "test", "path": str(HOST), "type": "stdio",
                "allowed_origins": [f"chrome-extension://{EXTENSION_ID}/"]}
    for directory in (home / ".config/google-chrome/NativeMessagingHosts", profile / "NativeMessagingHosts"):
        directory.mkdir(parents=True)
        (directory / "org.piotr.tab_sweep.json").write_text(json.dumps(manifest))
    env = {**os.environ, "HOME": str(home), "XDG_CONFIG_HOME": str(home / ".config"),
           "TAB_SWEEP_GH": str(script(tmp_path / "gh", FAKE_GH)), "TAB_SWEEP_SND": str(script(tmp_path / "snd", FAKE_SND)),
           "FAKE_GH_CALLS": str(tmp_path / "gh-calls"), "FAKE_SND_LOG": str(tmp_path / "snd-log"), "FAKE_MERGED": "o/r#1",
           "FAKE_MERGED_FILE": str(tmp_path / "merged"), "XDG_STATE_HOME": str(tmp_path / "state"),
           "AGENT_TMUX_TEST_SOCKET": "tab-sweep-e2e-" + uuid.uuid4().hex}
    env.pop("TAB_SWEEP_TO", None)
    pipe_in, to_chrome = os.pipe()
    from_chrome, pipe_out = os.pipe()
    log = (tmp_path / "chrome.log").open("w")
    # Branded Chrome ignores --load-extension, so load over the DevTools pipe (fd 3/4).
    browser = subprocess.Popen(
        [CHROME, "--headless", f"--user-data-dir={profile}", "--remote-debugging-pipe", "--enable-unsafe-extension-debugging",
         "--remote-debugging-port=0", "--no-first-run", "--no-default-browser-check", "--no-sandbox", "about:blank"],
        env=env, stdout=subprocess.DEVNULL, stderr=log, start_new_session=True, pass_fds=(3, 4),
        preexec_fn=lambda: (os.dup2(pipe_in, 3), os.dup2(pipe_out, 4)))
    os.close(pipe_in)
    os.close(pipe_out)

    def cleanup():
        subprocess.run(["tmux", "-L", env["AGENT_TMUX_TEST_SOCKET"], "kill-server"], capture_output=True)
        try:
            os.killpg(browser.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        browser.wait(timeout=10)
        log.close()
        os.close(to_chrome)
        os.close(from_chrome)
    request.addfinalizer(cleanup)

    def load():
        """Load (or, the second time, reload) the extension over the DevTools pipe."""
        os.write(to_chrome, json.dumps({"id": 1, "method": "Extensions.loadUnpacked", "params": {"path": str(EXTENSION)}}).encode() + b"\0")
        reply, deadline = b"", time.time() + 30
        while b"\0" not in reply and time.time() < deadline:
            if select.select([from_chrome], [], [], .5)[0]:
                reply += os.read(from_chrome, 65536)
        loaded = json.loads(reply.split(b"\0")[0] or b"{}")
        assert loaded.get("result", {}).get("id") == EXTENSION_ID, loaded
    load()
    active_port = profile / "DevToolsActivePort"
    for _ in range(300):
        if active_port.exists():
            break
        time.sleep(.1)
    port = int(active_port.read_text().splitlines()[0])
    cdp = CDP(json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json/version"))["webSocketDebuggerUrl"])
    worker = attach(cdp, port, f"chrome-extension://{EXTENSION_ID}/background.js")
    cdp.reload_extension = load
    cdp.tmux = ["tmux", "-L", env["AGENT_TMUX_TEST_SOCKET"], "-f", "/dev/null"]
    yield cdp, port, worker, tmp_path


def attach(cdp, port, url):
    """Attach to the target at url once it answers an evaluate; its session id."""
    for _ in range(100):
        targets = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json/list"))
        target = next((t for t in targets if t.get("url", "").startswith(url)), None)
        if target:
            session = cdp.command("Target.attachToTarget", {"targetId": target["id"], "flatten": True})["sessionId"]
            if run(cdp, session, "1") == 1:
                return session
        time.sleep(.1)
    pytest.fail(f"no target answered at {url}")


def run(cdp, session, expression):
    result = cdp.command("Runtime.evaluate", {"expression": expression, "awaitPromise": True, "returnByValue": True}, session)
    assert "exceptionDetails" not in result, result
    return result["result"].get("value")


def open_tabs(cdp, worker, specs):
    """Open tabs in order (url, pinned); their ids."""
    return run(cdp, worker, "(async()=>{const ids=[];for(const [url,pinned] of %s){ids.push((await chrome.tabs.create({url,pinned,active:false})).id)}return ids})()" % json.dumps(specs))


def open_urls(cdp, worker):
    return sorted(run(cdp, worker, "chrome.tabs.query({}).then(ts=>ts.map(t=>t.url||t.pendingUrl))"))


def sent(tmp_path):
    lines = (tmp_path / "snd-log").read_text().splitlines() if (tmp_path / "snd-log").exists() else []
    return [json.loads(line)["argv"] for line in lines]


def wait_text(cdp, session, prefix, seconds=15):
    for _ in range(int(seconds * 10)):
        text = run(cdp, session, "document.getElementById('status').textContent")
        if text.startswith(prefix):
            return text
        time.sleep(.1)
    pytest.fail(f"popup status stayed {text!r}, wanted {prefix!r}")


def test_sweep_closes_merged_prs_and_extra_copies_and_tells_nobody_by_default(chrome):
    cdp, _, worker, tmp_path = chrome
    merged, files, still_open, first, copy, pinned = open_tabs(cdp, worker, [
        [f"{PR}/1", False], [f"{PR}/1/files", False], [f"{PR}/2", False],
        ["https://example.com/dup", False], ["https://example.com/dup", False], [f"{PR}/1/checks", True]])
    result = run(cdp, worker, "sweep()")
    assert sorted(row["id"] for row in result["closed"]) == sorted([merged, files, copy]), result
    assert open_urls(cdp, worker) == sorted(["about:blank", f"{PR}/2", "https://example.com/dup", f"{PR}/1/checks"])
    assert sent(tmp_path) == [] and result["reported"] is False
    assert run(cdp, worker, "chrome.action.getBadgeText({})") == "3"


def test_a_copy_in_a_tab_group_stays_and_the_loose_copy_closes(chrome):
    cdp, _, worker, _ = chrome
    loose, agents = open_tabs(cdp, worker, [["https://example.com/g", False], ["https://example.com/g", False]])
    run(cdp, worker, "chrome.tabs.group({tabIds: [%d]}).then(()=>1)" % agents)
    assert [row["id"] for row in run(cdp, worker, "sweep()")["closed"]] == [loose]
    assert run(cdp, worker, "chrome.tabs.get(%d).then(t=>t.groupId>=0)" % agents) is True


def test_popup_lists_tabs_closes_on_click_and_reports_with_the_box_ticked(chrome):
    cdp, port, worker, tmp_path = chrome
    open_tabs(cdp, worker, [["https://example.com/a", False], ["https://example.com/a", False], [f"{PR}/1", False]])
    run(cdp, worker, "chrome.tabs.create({url: chrome.runtime.getURL('popup.html')}).then(()=>1)")
    popup = attach(cdp, port, f"chrome-extension://{EXTENSION_ID}/popup.html")
    assert wait_text(cdp, popup, "2 of") == "2 of 5 tabs to close:"
    assert run(cdp, popup, "[...document.querySelectorAll('li .why')].map(e=>e.textContent)") == ["merged", "duplicate"]
    assert sent(tmp_path) == [] and len(open_urls(cdp, worker)) == 5
    run(cdp, popup, "document.getElementById('report').click(), 1")
    assert run(cdp, popup, "new Promise(r=>setTimeout(()=>chrome.storage.local.get('report').then(s=>r(s.report)),200))") is True
    run(cdp, popup, "document.getElementById('close').click(), 1")
    assert wait_text(cdp, popup, "Closed") == "Closed 2 tabs, reported to Gordon."
    assert open_urls(cdp, worker).count("https://example.com/a") == 1
    assert sent(tmp_path) == [["--no-human", "-t", "triage", "Chrome tab sweep closed the tabs of 1 merged PR: o/r#1."]]


def test_popup_with_auto_close_sweeps_on_open_and_reports_when_ticked(chrome):
    cdp, port, worker, tmp_path = chrome
    open_tabs(cdp, worker, [["https://example.com/b", False], ["https://example.com/b", False], [f"{PR}/1", False]])
    run(cdp, worker, "chrome.storage.local.set({auto: true, report: true}).then(()=>chrome.tabs.create({url: chrome.runtime.getURL('popup.html')})).then(()=>1)")
    popup = attach(cdp, port, f"chrome-extension://{EXTENSION_ID}/popup.html")
    assert wait_text(cdp, popup, "Closed") == "Closed 2 tabs, reported to Gordon."
    assert len(sent(tmp_path)) == 1
    assert run(cdp, popup, "document.getElementById('report').checked") is True
    assert run(cdp, popup, "document.getElementById('auto').checked") is True
    assert open_urls(cdp, worker).count("https://example.com/b") == 1


def wait_for(cdp, session, expression, want, seconds=10):
    for _ in range(int(seconds * 10)):
        value = run(cdp, session, expression)
        if value == want:
            return value
        time.sleep(.1)
    pytest.fail(f"{expression} stayed {value!r}, wanted {want!r}")


def agent_pane(cdp):
    """A live pane on the test tmux server, standing in for an agent's."""
    subprocess.run(cdp.tmux + ["new-session", "-d", "-s", "agent"], check=True)
    return subprocess.run(cdp.tmux + ["display", "-p", "-t", "=agent:", "#{pane_id}"], capture_output=True, text=True, check=True).stdout.strip()


def test_auto_close_sweeps_in_the_background_and_spares_only_a_live_agents_group(chrome):
    cdp, _, worker, tmp_path = chrome
    agent, agents_pr, handoff, loose, first, copy = open_tabs(cdp, worker, [
        ["https://example.com/agent", False], [f"{PR}/1", False], [f"{PR}/1/commits", False], [f"{PR}/1/files", False],
        ["https://example.com/c", False], ["https://example.com/c", False]])
    run(cdp, worker, "chrome.tabs.group({tabIds: [%d, %d]}).then(()=>1)" % (agent, agents_pr))
    run(cdp, worker, "chrome.tabs.group({tabIds: [%d]}).then(()=>1)" % handoff)  # like the handoffs group
    map_tabs(tmp_path / "state", [(agent, agent_pane(cdp))])
    time.sleep(3)
    assert len(open_urls(cdp, worker)) == 7, "auto is off, so nothing closes on its own"
    run(cdp, worker, "chrome.storage.local.set({auto: true, report: true}).then(()=>1)")
    alive = "Promise.all(%s.map(id=>chrome.tabs.get(id).then(()=>true,()=>false)))"
    wait_for(cdp, worker, alive % json.dumps([agent, agents_pr, handoff, loose, first, copy]), [True, True, False, False, True, False])
    title = "chrome.action.getTitle({}).then(t=>t.replace(/at \\d\\d:\\d\\d$/, 'at HH:MM'))"
    wait_for(cdp, worker, title, "Tab sweep: auto-closed 3 tabs at HH:MM")  # set after the report
    assert run(cdp, worker, "chrome.action.getBadgeText({})") == "", "a background close leaves no number on the icon"
    assert sent(tmp_path) == [["--no-human", "-t", "triage", "Chrome tab sweep closed the tabs of 1 merged PR: o/r#1."]]
    open_tabs(cdp, worker, [["https://example.com/c", False]])
    wait_for(cdp, worker, "chrome.tabs.query({}).then(ts=>ts.filter(t=>(t.url||t.pendingUrl)==='https://example.com/c').length)", 1)
    wait_for(cdp, worker, title, "Tab sweep: auto-closed 1 tab at HH:MM")
    assert len(sent(tmp_path)) == 1, "a duplicate close is not reported"


def test_auto_close_sweeps_each_minute_so_a_pr_merged_in_a_still_tab_closes(chrome):
    cdp, _, worker, tmp_path = chrome
    assert run(cdp, worker, "chrome.alarms.get('sweep').then(a=>a.periodInMinutes)") == 1
    run(cdp, worker, "chrome.storage.local.set({auto: true}).then(()=>1)")
    still, = open_tabs(cdp, worker, [[f"{PR}/3", False]])
    time.sleep(3)
    assert run(cdp, worker, "chrome.tabs.get(%d).then(()=>true,()=>false)" % still) is True, "not merged yet"
    (tmp_path / "merged").write_text("o/r#3")
    # Fire the alarm now rather than wait a minute; no tab changes URL.
    run(cdp, worker, "chrome.alarms.create('sweep', {delayInMinutes: 0.01}).then(()=>1)")
    wait_for(cdp, worker, "chrome.tabs.get(%d).then(()=>true,()=>false)" % still, False)


def test_auto_close_keeps_the_older_copy_and_moves_piotr_to_it(chrome):
    cdp, _, worker, _ = chrome
    # The filler sits between them, so Chrome's own pick after a close would land on it.
    older, _filler = open_tabs(cdp, worker, [["https://example.com/o", False], ["https://example.com/filler", False]])
    run(cdp, worker, "chrome.storage.local.set({auto: true}).then(()=>1)")
    time.sleep(2)
    fresh = run(cdp, worker, "chrome.tabs.create({url: 'https://example.com/o', active: true}).then(t=>t.id)")
    alive = "Promise.all(%s.map(id=>chrome.tabs.get(id).then(t=>t.active,()=>null)))" % json.dumps([older, fresh])
    wait_for(cdp, worker, alive, [True, None])


def test_auto_close_sweeps_right_after_the_extension_reloads(chrome):
    cdp, port, worker, _ = chrome
    open_tabs(cdp, worker, [["https://example.com/r", False], ["https://example.com/r", False]])
    # Reload before the tick's own sweep fires, so only the reload can close the copy.
    run(cdp, worker, "chrome.storage.local.set({auto: true}).then(()=>1)")
    cdp.reload_extension()
    for _ in range(100):
        pages = [t for t in cdp.command("Target.getTargets")["targetInfos"] if t["url"] == "https://example.com/r"]
        if len(pages) == 1:
            break
        time.sleep(.1)
    assert len(pages) == 1
