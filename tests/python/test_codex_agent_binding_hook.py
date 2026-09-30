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
    group: str | None = None,
    tool_response: object = None,
    tmux_session: str | None = None,
) -> subprocess.CompletedProcess[str]:
    tool_input = {"name": agent_name}
    if group is not None:
        tool_input["group"] = group
    payload = {
        "hook_event_name": "PostToolUse",
        "session_id": "thread-123",
        "tool_name": tool_name,
        "tool_input": tool_input,
    }
    if tool_response is not None:
        payload["tool_response"] = tool_response
    # Never touch the real ledger or a real tmux server from a test.
    fake_tmux = codex_home / "fake-tmux"
    fake_tmux.write_text(
        "#!/bin/sh\n"
        + (f"printf '%s\\n' '{tmux_session}'\n" if tmux_session else "exit 1\n")
    )
    fake_tmux.chmod(0o755)
    env = {
        **os.environ,
        "CODEX_HOME": str(codex_home),
        "AGENTS_SESSION_LEDGER": str(codex_home / "agent-sessions.tsv"),
        "CODEX_TMUX_BIN": str(fake_tmux),
    }
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



class CodexAgentSessionLedgerTest(unittest.TestCase):
    def ledger(self, codex_home: Path) -> str:
        path = codex_home / "agent-sessions.tsv"
        return path.read_text() if path.exists() else ""

    def test_register_writes_the_session_row_the_bus_check_reads(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            codex_home = Path(directory)
            run_hook(
                codex_home, "mcp__agents__agent_register", "loft-prod-DEVOPS-1584",
                pane="%42", group="tasks", tmux_session="loft-prod-DEVOPS-1584",
                tool_response={"agent_id": "loft-prod-DEVOPS-1584-b56d8b96"},
            )
            self.assertEqual(
                self.ledger(codex_home),
                "loft-prod-DEVOPS-1584\tloft-prod-DEVOPS-1584\ttasks\tloft-prod-DEVOPS-1584-b56d8b96\n",
            )

    def test_register_reads_the_agent_id_from_mcp_text_content(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            codex_home = Path(directory)
            response = [{"type": "text", "text": json.dumps({"agent_id": "w-1a2b"})}]
            run_hook(
                codex_home, "mcp__agents__agent_register", "w", pane="%42",
                group="tasks", tmux_session="w-session", tool_response=response,
            )
            self.assertEqual(self.ledger(codex_home), "w-session\tw\ttasks\tw-1a2b\n")

    def test_register_without_a_pane_writes_no_row(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            codex_home = Path(directory)
            run_hook(codex_home, "mcp__agents__agent_register", "w", group="tasks",
                     tmux_session="w-session")
            self.assertEqual(self.ledger(codex_home), "")

    def test_deregister_removes_only_that_agents_rows(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            codex_home = Path(directory)
            (codex_home / "agent-sessions.tsv").write_text(
                "task\ttriage\ttasks\ttriage-1\n"
                "w-session\tw\ttasks\tw-1\n"
            )
            run_hook(codex_home, "mcp__agents__agent_deregister", "w")
            self.assertEqual(self.ledger(codex_home), "task\ttriage\ttasks\ttriage-1\n")


if __name__ == "__main__":
    unittest.main()
