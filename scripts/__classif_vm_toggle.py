#!/usr/bin/env python3
"""Switch classif between vind-node's forwarded Ollama and this PC."""

import json
import os
import pathlib
import stat
import subprocess
import sys
import tempfile


MODEL = "winnow:12b-q4_K_M"
VM_HOST = "127.0.0.1:11435"
PC_HOST = "localhost:11434"


def paths():
    home = pathlib.Path.home()
    return (
        home / ".claude/config/quick-decisions.json",
        home / ".config/classif/hosts",
        home / ".local/state/classif-vm/pc-mode",
    )


def target(mode):
    host = VM_HOST if mode == "vm" else PC_HOST
    return f"{host}={MODEL}"


def read_mode():
    config_path, hosts_path, pc_flag = paths()
    try:
        config = json.loads(config_path.read_text())
        configured = config["classif_hosts"]
        listed = [line.strip() for line in hosts_path.read_text().splitlines() if line.strip() and not line.lstrip().startswith("#")]
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(f"classif route is unreadable: {exc}", file=sys.stderr)
        return None
    vm = target("vm")
    pc = target("pc")
    flag = pc_flag.exists()
    if configured == vm and listed == [vm] and not flag:
        return "vm"
    if configured == pc and listed == [pc] and flag:
        return "pc"
    print("classif route files or mode flag disagree; refusing to guess", file=sys.stderr)
    return None


def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    # Resolve stow symlinks so the managed file changes while the link remains.
    path = path.resolve()
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644
    fd, tmp = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def write_route(mode):
    config_path, hosts_path, _ = paths()
    old_config = config_path.read_text()
    old_hosts = hosts_path.read_text()
    config = json.loads(old_config)
    config["classif_hosts"] = target(mode)
    new_config = json.dumps(config, indent=2) + "\n"
    try:
        atomic_write(config_path, new_config)
        atomic_write(hosts_path, f"# managed by classif on VM / this PC toggle\n{target(mode)}\n")
    except Exception:
        atomic_write(config_path, old_config)
        atomic_write(hosts_path, old_hosts)
        raise


def run(*args):
    subprocess.run(args, check=True)


def set_mode(mode):
    config_path, _, pc_flag = paths()
    pc_flag.parent.mkdir(parents=True, exist_ok=True)
    if mode == "vm":
        pc_flag.unlink(missing_ok=True)
        try:
            run("systemctl", "--user", "enable", "--now", "classif-vm-tunnel.service")
            write_route(mode)
            local_models = subprocess.run(
                ["curl", "--fail", "--silent", "--show-error", "--max-time", "2",
                 "http://localhost:11434/api/ps"],
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, check=False,
            )
            if local_models.returncode == 0:
                loaded = json.loads(local_models.stdout).get("models", [])
                if any(item.get("name", "").split(":", 1)[0] == MODEL.split(":", 1)[0]
                       for item in loaded):
                    run("curl", "--fail", "--silent", "--show-error", "--max-time", "5",
                        "http://localhost:11434/api/generate", "-d",
                        '{"model":"winnow:12b-q4_K_M","prompt":"","keep_alive":0}')
        except Exception:
            # Keep the toggle state recoverable if any step before route setup fails.
            if read_mode() != "vm":
                pc_flag.touch()
            raise
    else:
        write_route(mode)
        pc_flag.touch()
        run("systemctl", "--user", "stop", "classif-vm-tunnel.service")


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in {"status", "vm", "pc"}:
        print("usage: __classif_vm_toggle.py status|vm|pc", file=sys.stderr)
        return 2
    action = sys.argv[1]
    if action == "status":
        state = read_mode()
        return 2 if state is None else (0 if state == "vm" else 1)
    try:
        set_mode(action)
    except (OSError, subprocess.CalledProcessError, ValueError) as exc:
        print(f"classif {action} switch failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
