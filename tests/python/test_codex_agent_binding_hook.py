import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from urllib.parse import quote


SCRIPT = Path(__file__).parents[2] / "scripts" / "__codex_agent_binding_hook.py"


def run_hook(
    codex_home: Path,
    tool_name: str,
    agent_name: str,
    socket_path: str | None = None,
    pane: str | None = None,
    status_script: Path | None = None,
    status_log: Path | None = None,
) -> subprocess.CompletedProcess[str]:
    payload = {
        "hook_event_name": "PostToolUse",
        "session_id": "thread-123",
        "tool_name": tool_name,
        "tool_input": {"name": agent_name},
    }
    env = {**os.environ, "CODEX_HOME": str(codex_home)}
    for name in (
        "CODEX_APP_SERVER_SOCKET",
        "CODEX_TMUX_PANE",
        "TMUX_PANE",
        "CODEX_TMUX_AGENT_STATUS",
        "CODEX_TMUX_AGENT_STATUS_LOG",
    ):
        env.pop(name, None)
    if socket_path is not None:
        env["CODEX_APP_SERVER_SOCKET"] = socket_path
    if pane is not None:
        env["CODEX_TMUX_PANE"] = pane
    if status_script is not None:
        env["CODEX_TMUX_AGENT_STATUS"] = str(status_script)
    if status_log is not None:
        env["CODEX_TMUX_AGENT_STATUS_LOG"] = str(status_log)
    return subprocess.run(
        ["python3", str(SCRIPT)], input=json.dumps(payload), text=True,
        capture_output=True, env=env, check=False,
    )


def make_status_script(directory: Path) -> tuple[Path, Path]:
    script = directory / "tmux-agent-status"
    log = directory / "tmux-agent-status.log"
    script.write_text(
        "#!/bin/sh\n"
        "printf '%s\\n' \"$*\" >> \"$CODEX_TMUX_AGENT_STATUS_LOG\"\n"
    )
    script.chmod(0o755)
    return script, log


class CodexAgentBindingHookTest(unittest.TestCase):
    def test_register_binds_agent_name_to_codex_thread(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            codex_home = Path(directory)
            result = run_hook(codex_home, "mcp__agents__agent_register", "greta/kube")

            binding = codex_home / "agent-bindings" / f"{quote('greta/kube', safe='')}.json"
            self.assertEqual(result.returncode, 0)
            self.assertEqual(json.loads(binding.read_text()), {
                "agent": "greta/kube", "thread_id": "thread-123",
            })

    def test_register_records_pane_specific_app_server_socket(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            codex_home = Path(directory)
            result = run_hook(
                codex_home,
                "mcp__agents__agent_register",
                "greta",
                "/codex/app-server-control/pane/app-server-control.sock",
            )

            binding = codex_home / "agent-bindings" / "greta.json"
            self.assertEqual(result.returncode, 0)
            self.assertEqual(json.loads(binding.read_text()), {
                "agent": "greta",
                "thread_id": "thread-123",
                "socket_path": "/codex/app-server-control/pane/app-server-control.sock",
            })

    def test_deregister_removes_the_binding(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            codex_home = Path(directory)
            run_hook(codex_home, "mcp__agents__agent_register", "greta")
            result = run_hook(codex_home, "mcp__agents__agent_deregister", "greta")

            self.assertEqual(result.returncode, 0)
            self.assertFalse((codex_home / "agent-bindings" / "greta.json").exists())

    def test_register_sets_the_pane_agent_name(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            status_script, status_log = make_status_script(root)

            result = run_hook(
                root,
                "mcp__agents__agent_register",
                "greta",
                pane="%42",
                status_script=status_script,
                status_log=status_log,
            )

            self.assertEqual(result.returncode, 0)
            self.assertEqual(status_log.read_text(), "set greta %42\n")

    def test_deregister_clears_only_the_matching_pane_agent_name(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            status_script, status_log = make_status_script(root)

            result = run_hook(
                root,
                "mcp__agents__agent_deregister",
                "greta",
                pane="%42",
                status_script=status_script,
                status_log=status_log,
            )

            self.assertEqual(result.returncode, 0)
            self.assertEqual(status_log.read_text(), "clear %42 greta\n")


if __name__ == "__main__":
    unittest.main()
