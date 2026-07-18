#!/usr/bin/env python3
"""Bind an agents MCP identity to the Codex thread that registered it."""

import json
import os
import sys
from pathlib import Path
from urllib.parse import quote


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, OSError):
        return 0

    tool_name = payload.get("tool_name") or payload.get("toolName") or ""
    tool_input = payload.get("tool_input") or payload.get("toolInput") or {}
    session_id = payload.get("session_id") or payload.get("sessionId") or ""
    agent_name = tool_input.get("name") if isinstance(tool_input, dict) else ""
    if not agent_name:
        return 0

    codex_home = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))
    binding_dir = codex_home / "agent-bindings"
    binding_path = binding_dir / f"{quote(agent_name, safe='')}.json"

    if tool_name == "mcp__agents__agent_deregister":
        binding_path.unlink(missing_ok=True)
        return 0
    if tool_name != "mcp__agents__agent_register" or not session_id:
        return 0

    binding_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = binding_path.with_suffix(".json.tmp")
    temporary.write_text(json.dumps({"agent": agent_name, "thread_id": session_id}) + "\n")
    temporary.chmod(0o600)
    temporary.replace(binding_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
