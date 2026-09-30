#!/usr/bin/env python3
"""Bind an agents MCP identity to the Codex thread that registered it."""

import json
import os
import subprocess
import sys
from pathlib import Path
from urllib.parse import quote


def update_tmux_agent_label(tool_name: str, agent_name: str) -> None:
    pane = os.environ.get("CODEX_TMUX_PANE") or os.environ.get("TMUX_PANE", "")
    if not pane:
        return

    status_script = Path(
        os.environ.get(
            "CODEX_TMUX_AGENT_STATUS",
            Path.home() / ".claude" / "scripts" / "__tmux_agent_status.sh",
        )
    )
    if not status_script.is_file() or not os.access(status_script, os.X_OK):
        return

    if tool_name == "mcp__agents__agent_register":
        args = ["set", agent_name, pane]
    elif tool_name == "mcp__agents__agent_deregister":
        args = ["clear", pane, agent_name]
    else:
        return

    try:
        subprocess.run(
            [str(status_script), *args],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except OSError:
        pass


# Session ledger shared with the Claude register hook
# (~/.claude/scripts/__mcp_agent_registration_hook.sh): one tab-separated row
# of session, name, group, agent_id per registration. __spawn_agent_bus_check.sh
# reads it as the only proof a register call landed, so a Codex worker that
# registered but wrote no row was nudged as unregistered.
def ledger_path() -> Path:
    return Path(
        os.environ.get(
            "AGENTS_SESSION_LEDGER",
            Path.home() / ".claude" / "data" / "agent-sessions.tsv",
        )
    )


def tmux_session_name(pane: str) -> str:
    tmux = os.environ.get("CODEX_TMUX_BIN", "tmux")
    try:
        result = subprocess.run(
            [tmux, "display-message", "-p", "-t", pane, "#{session_name}"],
            capture_output=True,
            text=True,
            check=False,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return result.stdout.strip() if result.returncode == 0 else ""


def response_agent_id(response: object) -> str:
    if isinstance(response, str):
        try:
            response = json.loads(response)
        except json.JSONDecodeError:
            return ""
    if isinstance(response, dict):
        if isinstance(response.get("agent_id"), str):
            return response["agent_id"]
        for key in ("content", "structuredContent", "structured_content", "result"):
            found = response_agent_id(response.get(key))
            if found:
                return found
        return response_agent_id(response.get("text"))
    if isinstance(response, list):
        for item in response:
            found = response_agent_id(item)
            if found:
                return found
    return ""


def ledger_append(agent_name: str, group: str, agent_id: str) -> None:
    pane = os.environ.get("CODEX_TMUX_PANE") or os.environ.get("TMUX_PANE", "")
    session = tmux_session_name(pane) if pane else ""
    if not session:
        return
    path = ledger_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a") as ledger:
            ledger.write(f"{session}\t{agent_name}\t{group}\t{agent_id or agent_name}\n")
    except OSError:
        pass


def ledger_remove(agent_name: str) -> None:
    path = ledger_path()
    if not path.is_file():
        return
    try:
        kept = [
            line
            for line in path.read_text().splitlines(keepends=True)
            if line.split("\t")[1:2] != [agent_name]
        ]
        temporary = path.with_name(path.name + ".tmp")
        temporary.write_text("".join(kept))
        temporary.replace(path)
    except OSError:
        pass


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
        update_tmux_agent_label(tool_name, agent_name)
        ledger_remove(agent_name)
        return 0
    if tool_name != "mcp__agents__agent_register":
        return 0
    update_tmux_agent_label(tool_name, agent_name)
    group = tool_input.get("group") or "default"
    response = payload.get("tool_response") or payload.get("toolResponse")
    ledger_append(agent_name, group, response_agent_id(response))
    if not session_id:
        return 0

    binding_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = binding_path.with_suffix(".json.tmp")
    binding = {"agent": agent_name, "thread_id": session_id}
    socket_path = os.environ.get("CODEX_APP_SERVER_SOCKET", "")
    if socket_path:
        binding["socket_path"] = socket_path
    temporary.write_text(json.dumps(binding) + "\n")
    temporary.chmod(0o600)
    temporary.replace(binding_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
