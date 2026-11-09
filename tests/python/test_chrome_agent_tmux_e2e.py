"""Exercise Chrome activation through the extension and native tmux host."""
import base64
import hashlib
import json
import os
import pty
import shutil
import signal
import socket
import struct
import subprocess
import tempfile
import time
import urllib.request
import uuid
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[2]
CHROME = os.environ.get("AGENT_TAB_TEST_CHROME") or shutil.which("google-chrome")
XVFB_RUN = shutil.which("xvfb-run")
TMUX = shutil.which("tmux")
EXTENSION = ROOT / ".config/chrome-agent-tmux"
HOST = ROOT / "scripts/__chrome_agent_tmux.py"


def extension_id():
    manifest = json.loads((EXTENSION / "manifest.json").read_text())
    der = base64.b64decode(manifest["key"])
    digest = hashlib.sha256(der).digest()[:16]
    return "".join(chr(ord("a") + (byte >> shift & 0x0f)) for byte in digest for shift in (4, 0))


class CDP:
    """Tiny local WebSocket client for Chrome's remote debugging endpoint."""
    def __init__(self, url):
        from urllib.parse import urlparse
        parsed = urlparse(url)
        self.sock = socket.create_connection((parsed.hostname, parsed.port), timeout=5)
        self.sock.settimeout(30)
        key = base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall((f"GET {parsed.path} HTTP/1.1\r\nHost: {parsed.netloc}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
        response = b""
        while b"\r\n\r\n" not in response:
            response += self.sock.recv(4096)
        assert b" 101 " in response.split(b"\r\n", 1)[0], response[:200]
        self.buffer = response.split(b"\r\n\r\n", 1)[1]
        self.sequence = 0

    def command(self, method, params=None, session=None):
        self.sequence += 1
        command_id = self.sequence
        payload = json.dumps({"id": command_id, "method": method, "params": params or {}, **({"sessionId": session} if session else {})}).encode()
        mask = os.urandom(4)
        size = len(payload)
        header = bytes([0x81, 0x80 | (size if size < 126 else 126)])
        if size >= 126:
            header += struct.pack("!H", size)
        self.sock.sendall(header + mask + bytes(byte ^ mask[i % 4] for i, byte in enumerate(payload)))
        while True:
            data = self._frame()
            message = json.loads(data)
            if message.get("id") == command_id:
                if "error" in message:
                    raise RuntimeError(message["error"])
                return message.get("result", {})

    def _frame(self):
        while len(self.buffer) < 2:
            self.buffer += self.sock.recv(65536)
        first, second = self.buffer[:2]
        self.buffer = self.buffer[2:]
        size = second & 0x7f
        if size == 126:
            while len(self.buffer) < 2:
                self.buffer += self.sock.recv(65536)
            size = struct.unpack("!H", self.buffer[:2])[0]
            self.buffer = self.buffer[2:]
        elif size == 127:
            while len(self.buffer) < 8:
                self.buffer += self.sock.recv(65536)
            size = struct.unpack("!Q", self.buffer[:8])[0]
            self.buffer = self.buffer[8:]
        mask = b""
        if second & 0x80:
            while len(self.buffer) < 4:
                self.buffer += self.sock.recv(65536)
            mask, self.buffer = self.buffer[:4], self.buffer[4:]
        while len(self.buffer) < size:
            self.buffer += self.sock.recv(65536)
        payload, self.buffer = self.buffer[:size], self.buffer[size:]
        if mask:
            payload = bytes(byte ^ mask[i % 4] for i, byte in enumerate(payload))
        if first & 0x0f == 9:
            self.sock.sendall(bytes([0x8a, len(payload)]) + payload)
            return self._frame()
        return payload


@pytest.fixture
def chrome_with_tmux(tmp_path, request):
    """Start private Chrome and tmux instances; always tear them down."""
    socket_name = "agent-tab-e2e-" + uuid.uuid4().hex
    tmux = [TMUX, "-L", socket_name, "-f", "/dev/null"]
    profile = tmp_path / "chrome-profile"
    home = tmp_path / "home"
    host_dirs = [home / ".config/google-chrome/NativeMessagingHosts", home / ".config/google-chrome-for-testing/NativeMessagingHosts", home / ".config/chromium/NativeMessagingHosts", profile / "NativeMessagingHosts"]
    for host_dir in host_dirs:
        host_dir.mkdir(parents=True)
    host_manifest = {
        "name": "org.piotr.agent_tab_tmux", "description": "test host",
        "path": str(HOST), "type": "stdio",
        "allowed_origins": [f"chrome-extension://{extension_id()}/"],
    }
    for host_dir in host_dirs:
        (host_dir / "org.piotr.agent_tab_tmux.json").write_text(json.dumps(host_manifest))
        os.chmod(host_dir / "org.piotr.agent_tab_tmux.json", 0o600)
    env = {**os.environ, "HOME": str(home), "XDG_CONFIG_HOME": str(home / ".config"), "AGENT_TMUX_TEST_SOCKET": socket_name}
    browser = None
    browser_log = (tmp_path / "chrome.log").open("w")
    client = None
    master = slave = None

    def cleanup():
        if browser is not None:
            try:
                os.killpg(browser.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                browser.wait(timeout=10)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(browser.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                browser.wait(timeout=5)
        browser_log.close()
        subprocess.run(tmux + ["kill-server"], capture_output=True)
        if client is not None:
            client.wait(timeout=5)
        if master is not None:
            os.close(master)
        if slave is not None:
            os.close(slave)

    request.addfinalizer(cleanup)
    subprocess.run(tmux + ["new-session", "-d", "-s", "start"], check=True)
    subprocess.run(tmux + ["new-session", "-d", "-s", "agent"], check=True)
    subprocess.run(tmux + ["set-option", "-p", "-t", "=agent:.0", "@agent_name", "agent"], check=True)
    master, slave = pty.openpty()
    client = subprocess.Popen(tmux + ["attach-session", "-t", "=start"], stdin=slave, stdout=slave, stderr=slave, env={**env, "TERM": "xterm"})
    for _ in range(100):
        if subprocess.run(tmux + ["list-clients"], capture_output=True).stdout:
            break
        time.sleep(.02)
    else:
        pytest.fail("tmux client failed to attach")

    browser = subprocess.Popen(
        [XVFB_RUN, "-a", CHROME, f"--user-data-dir={profile}",
         f"--load-extension={EXTENSION}", "--no-first-run", "--no-default-browser-check",
         "--no-sandbox", "--remote-debugging-port=0", "--enable-logging=stderr", "--log-level=1", "about:blank"],
        env=env, stdout=subprocess.DEVNULL, stderr=browser_log, start_new_session=True,
    )
    active_port = profile / "DevToolsActivePort"
    for _ in range(300):
        if browser.poll() is not None:
            pytest.fail(f"Chrome exited with {browser.returncode}")
        if active_port.exists():
            break
        time.sleep(.1)
    else:
        pytest.fail("Chrome remote debugging endpoint did not start")
    port = int(active_port.read_text().splitlines()[0])
    browser_ws = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json/version"))["webSocketDebuggerUrl"]
    cdp = CDP(browser_ws)
    extension_target = None
    for _ in range(100):
        targets = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json/list"))
        extension_target = next((item for item in targets if item.get("type") == "service_worker" and item.get("url", "").startswith(f"chrome-extension://{extension_id()}/background.js")), None)
        if extension_target:
            break
        time.sleep(.1)
    if not extension_target:
        pytest.fail("Chrome did not load the unpacked extension service worker")
    attached = cdp.command("Target.attachToTarget", {"targetId": extension_target["id"], "flatten": True})["sessionId"]
    yield tmux, cdp, attached


def eval_extension(cdp, session, expression):
    return cdp.command("Runtime.evaluate", {"expression": expression, "awaitPromise": True, "returnByValue": True}, session)


def selected_session(tmux):
    return subprocess.check_output(tmux + ["list-clients", "-F", "#{session_name}"], text=True).strip()


def test_chrome_activation_switches_agent_and_ignores_unowned_tab(chrome_with_tmux):
    tmux, cdp, session = chrome_with_tmux
    unowned = eval_extension(cdp, session, "(async()=>{let t=await chrome.tabs.create({url:'about:blank',active:true});return t.id})()")
    assert "exceptionDetails" not in unowned, unowned
    assert unowned.get("result", {}).get("type") == "number", unowned
    time.sleep(.5)
    assert selected_session(tmux) == "start"

    owned = eval_extension(cdp, session, "({permissions:chrome.runtime.getManifest().permissions, tabs:typeof chrome.tabs, tabGroups:typeof chrome.tabGroups, group:typeof chrome.tabs.group, updateGroup:typeof chrome.tabGroups?.update})")
    assert owned.get("result", {}).get("value", {}).get("updateGroup") == "function", owned
    owned = eval_extension(cdp, session, "(async()=>{let t=await chrome.tabs.create({url:'about:blank',active:false});let g=await chrome.tabs.group({tabIds:[t.id]});await chrome.tabGroups.update(g,{title:'agent'});await chrome.tabs.update(t.id,{active:true});return t.id})()")
    assert owned.get("result", {}).get("type") == "number", owned
    for _ in range(50):
        if selected_session(tmux) == "agent":
            break
        time.sleep(.1)
    if selected_session(tmux) != "agent":
        diagnostics = eval_extension(cdp, session, "(async()=>{let t=await chrome.tabs.query({active:true});let w=await chrome.windows.get(t[0].windowId);let g=await chrome.tabGroups.get(t[0].groupId);return {windowFocused:w.focused,groupTitle:g.title}})()")
        pytest.fail(f"activation did not switch tmux; diagnostics: {diagnostics}")

    activate_unowned = eval_extension(cdp, session, "(async()=>{let t=await chrome.tabs.create({url:'about:blank',active:false});await chrome.tabs.update(t.id,{active:true});return t.id})()")
    assert activate_unowned.get("result", {}).get("type") == "number", activate_unowned
    time.sleep(.5)
    assert selected_session(tmux) == "agent"
