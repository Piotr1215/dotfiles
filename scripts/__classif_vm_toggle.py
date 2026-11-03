#!/usr/bin/env python3
"""Select Piotr's interactive classif Ollama target."""

import os
import pathlib
import stat
import sys
import tempfile


MODEL = "winnow:12b-q4_K_M"
VM_HOST = "127.0.0.1:11435"
PC_HOST = "localhost:11434"


def paths():
    home = pathlib.Path.home()
    return home / ".config/classif/hosts", home / ".local/state/classif-vm/pc-mode"


def target(mode):
    host = VM_HOST if mode == "vm" else PC_HOST
    return f"{host}={MODEL}"


def read_mode():
    hosts_path, pc_flag = paths()
    try:
        listed = [line.strip() for line in hosts_path.read_text().splitlines()
                  if line.strip() and not line.lstrip().startswith("#")]
    except OSError as exc:
        print(f"interactive classif route is unreadable: {exc}", file=sys.stderr)
        return None
    if listed == [target("vm")] and not pc_flag.exists():
        return "vm"
    if listed == [target("pc")] and pc_flag.exists():
        return "pc"
    print("interactive classif route and mode flag disagree; refusing to guess", file=sys.stderr)
    return None


def write_hosts(path, mode):
    path.parent.mkdir(parents=True, exist_ok=True)
    # Resolve stow symlinks so the managed file changes while the link remains.
    path = path.resolve()
    file_mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644
    fd, tmp = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(f"# managed by my classif target toggle\n{target(mode)}\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(tmp, file_mode)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def set_mode(mode):
    hosts_path, pc_flag = paths()
    pc_flag.parent.mkdir(parents=True, exist_ok=True)
    write_hosts(hosts_path, mode)
    if mode == "pc":
        pc_flag.touch()
    else:
        pc_flag.unlink(missing_ok=True)


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
    except (OSError, ValueError) as exc:
        print(f"interactive classif {action} switch failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
