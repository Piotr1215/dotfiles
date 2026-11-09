#!/usr/bin/env python3
"""Native messaging host for switching the sole attached tmux client."""
import json
import os
import struct
import subprocess
import sys

MAX_MESSAGE = 4096


def run_tmux(*args):
    command = ["tmux"]
    socket = os.environ.get("AGENT_TMUX_TEST_SOCKET")
    if socket:
        command += ["-L", socket, "-f", "/dev/null"]
    return subprocess.run(command + list(args), text=True, capture_output=True, check=False)


def handle(message):
    owner = message.get("owner") if isinstance(message, dict) else None
    if not isinstance(owner, str) or not owner or len(owner) > 200 or any(c in owner for c in "\n\r\0"):
        return {"switched": False}
    panes = run_tmux("list-panes", "-a", "-F", "#{session_name}\t#{@agent_name}")
    if panes.returncode or f"{owner}\t{owner}" not in panes.stdout.splitlines():
        return {"switched": False}
    clients = run_tmux("list-clients", "-F", "#{client_tty}")
    attached = clients.stdout.splitlines() if clients.returncode == 0 else []
    if len(attached) != 1:
        return {"switched": False}
    result = run_tmux("switch-client", "-c", attached[0], "-t", "=" + owner)
    return {"switched": result.returncode == 0}


def main():
    header = sys.stdin.buffer.read(4)
    if len(header) != 4:
        return
    length = struct.unpack("=I", header)[0]
    if length > MAX_MESSAGE:
        return
    payload = sys.stdin.buffer.read(length)
    if len(payload) != length:
        return
    try:
        reply = handle(json.loads(payload))
    except (ValueError, OSError):
        reply = {"switched": False}
    data = json.dumps(reply).encode()
    sys.stdout.buffer.write(struct.pack("=I", len(data)) + data)
    sys.stdout.buffer.flush()


if __name__ == "__main__":
    main()
