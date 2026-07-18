import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from urllib.parse import quote


SCRIPT = Path(__file__).parents[2] / "scripts" / "__codex_agent_binding_hook.py"


def run_hook(codex_home: Path, tool_name: str, agent_name: str) -> subprocess.CompletedProcess[str]:
    payload = {
        "hook_event_name": "PostToolUse",
        "session_id": "thread-123",
        "tool_name": tool_name,
        "tool_input": {"name": agent_name},
    }
    env = {**os.environ, "CODEX_HOME": str(codex_home)}
    return subprocess.run(
        ["python3", str(SCRIPT)], input=json.dumps(payload), text=True,
        capture_output=True, env=env, check=False,
    )


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

    def test_deregister_removes_the_binding(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            codex_home = Path(directory)
            run_hook(codex_home, "mcp__agents__agent_register", "greta")
            result = run_hook(codex_home, "mcp__agents__agent_deregister", "greta")

            self.assertEqual(result.returncode, 0)
            self.assertFalse((codex_home / "agent-bindings" / "greta.json").exists())


if __name__ == "__main__":
    unittest.main()
