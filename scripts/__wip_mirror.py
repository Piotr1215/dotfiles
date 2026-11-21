#!/usr/bin/env python3
"""Keep real-time, versioned copies of serval's work files on its NVMe."""

import argparse
from contextlib import contextmanager
from datetime import datetime
import errno
from functools import partial
import logging
import os
from pathlib import Path
import pwd
import queue
import select
import signal
import socket
import stat
import subprocess
import threading
import time

from __lib_wip_fanotify import CLOSE_WRITE, CREATE, MOVED_TO, OVERFLOW, Fanotify
from __lib_wip_mirror import EXCLUDED, Mirror

DEFAULT_MOUNT = Path("/mnt/nvme-backup")
DEFAULT_UUID = "d74106d0-1b12-4d65-873d-d69ed3a729e6"
DEFAULT_HOME = Path("/home/decoder")
DEFAULT_NTFY = "https://ntfy.sh/homelab-piotr1215-backup"
DIR_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
POLL_SECONDS = 1
QUEUE_LIMIT = 16384
TARGET_IO_ERRORS = {errno.EIO, errno.ENODEV, errno.ENOSPC, errno.EROFS, errno.ESTALE}


class Drive:
    """Identify the destination by UUID and pin the verified directory."""

    def __init__(self, mount: Path, uuid: str, directory: str):
        self.mount = mount
        self.uuid = uuid
        self.directory = directory
        if not mount.is_absolute() or Path(directory).name != directory or directory in ("", ".", ".."):
            raise ValueError("expected an absolute mount path and a single destination directory name")
        if Path(uuid).name != uuid or uuid in ("", ".", ".."):
            raise ValueError("expected a filesystem UUID")

    def identity(self) -> int | None:
        mount_name = os.fsencode(self.mount)
        for raw, escaped in ((b"\\", b"\\134"), (b" ", b"\\040"), (b"\t", b"\\011"), (b"\n", b"\\012")):
            mount_name = mount_name.replace(raw, escaped)
        try:
            expected = (Path("/dev/disk/by-uuid") / self.uuid).stat()
        except FileNotFoundError:
            return None
        with open("/proc/self/mountinfo", "rb") as mounts:
            for line in mounts:
                prefix, suffix = line.split(b" - ", 1)
                fields = prefix.split()
                filesystem, source, _ = suffix.split()
                if fields[4] != mount_name or filesystem != b"btrfs":
                    continue
                try:
                    device = os.stat(source)
                except FileNotFoundError:
                    continue
                if stat.S_ISBLK(device.st_mode) and device.st_rdev == expected.st_rdev:
                    return int(fields[0])
        return None

    @contextmanager
    def open(self, identity: int):
        mount_fd = os.open(self.mount, DIR_FLAGS)
        try:
            if mount_id(mount_fd) != identity:
                raise OSError(errno.ESTALE, "NVMe mount changed during verification")
            target_fd = os.open(self.directory, DIR_FLAGS, dir_fd=mount_fd)
            try:
                if mount_id(target_fd) != identity:
                    raise ValueError("WIP destination is mounted separately from the verified NVMe")
                yield Path(f"/proc/self/fd/{target_fd}")
            finally:
                os.close(target_fd)
        finally:
            os.close(mount_fd)


def mount_id(descriptor: int) -> int:
    with open(f"/proc/self/fdinfo/{descriptor}", encoding="ascii") as info:
        return next(int(line.split()[1]) for line in info if line.startswith("mnt_id:"))


def in_scope(path: Path, roots: tuple[Path, ...]) -> bool:
    for root in roots:
        if path.is_relative_to(root):
            return not EXCLUDED.intersection(path.relative_to(root).parts)
    return False


class Inbox:
    """Drain the kernel queue while the writer scans or copies large files."""

    def __init__(self, stopped: threading.Event):
        self.paths = queue.Queue(maxsize=QUEUE_LIMIT)
        self.loss = threading.Event()
        self.stopped = stopped
        self.error = None

    def offer(self, path: Path):
        try:
            self.paths.put_nowait(path)
        except queue.Full:
            self.loss.set()

    def capture(self, reader: Fanotify, roots: tuple[Path, ...]):
        try:
            while not self.stopped.is_set():
                ready, _, _ = select.select([reader], [], [], POLL_SECONDS)
                if not ready:
                    continue
                for event in reader.read():
                    if event.mask & OVERFLOW:
                        self.loss.set()
                    elif event.path is not None and in_scope(event.path, roots):
                        # Regular CREATE can precede the first write. CLOSE_WRITE
                        # copies the finished file, and MOVED_TO handles atomic saves.
                        if event.mask & (CLOSE_WRITE | MOVED_TO) or (
                            event.mask & CREATE and event.path.is_symlink()
                        ):
                            self.offer(event.path)
        except Exception as error:
            self.error = error
            self.stopped.set()


def alert_missing(source_user: str, ntfy: str | None):
    message = "NVMe WIP mirror paused because the backup drive is unavailable"
    logging.warning(message)
    if ntfy is None:
        return
    account = pwd.getpwnam(source_user)
    notify_log = Path(account.pw_dir) / ".local/state/notifications.log"
    timestamp = datetime.now().strftime("%F %T")
    try:
        subprocess.run(
            ["/usr/bin/tee", "-a", "--", str(notify_log)],
            input=f"{timestamp}\tservice-health\t{message}\n", text=True,
            stdout=subprocess.DEVNULL, user=account.pw_uid, group=account.pw_gid,
            extra_groups=[], check=True, timeout=5,
        )
    except (OSError, subprocess.SubprocessError) as error:
        logging.warning("could not write mirror notification: %s", error)
    try:
        subprocess.run(
            ["/usr/bin/curl", "-fsS", "-o", "/dev/null", "--connect-timeout", "5", "-m", "15",
             "-H", f"Title: WIP mirror on {socket.gethostname()}",
             "-H", "Priority: high", "--data-binary", message, ntfy],
            check=True,
        )
    except (OSError, subprocess.SubprocessError) as error:
        logging.warning("could not publish mirror notification: %s", error)


@contextmanager
def open_mirror(drive: Drive, identity: int, roots: tuple[Path, ...], source_user: str):
    # Pin the target only while working. An idle mirror must permit a clean eject.
    with drive.open(identity) as target:
        yield Mirror(target, roots, source_user=source_user)


def serve_drive(inbox: Inbox, drive: Drive, identity: int, connect):
    inbox.loss.clear()
    logging.info("catching up WIP mirror")
    with connect() as mirror:
        mirror.catch_up()
    logging.info("WIP mirror catch-up complete")
    next_probe = 0.0
    while not inbox.stopped.is_set():
        now = time.monotonic()
        if now >= next_probe:
            if drive.identity() != identity:
                return
            next_probe = now + POLL_SECONDS
        if inbox.loss.is_set():
            # Clear before scanning so a second loss during the scan triggers
            # another scan. Events already in the inbox still get replayed.
            inbox.loss.clear()
            logging.warning("fanotify event loss, rescanning WIP mirror")
            with connect() as mirror:
                mirror.catch_up()
        try:
            path = inbox.paths.get(timeout=POLL_SECONDS)
        except queue.Empty:
            continue
        try:
            with connect() as mirror:
                mirror.sync(path)
        except OSError as error:
            if error.errno in TARGET_IO_ERRORS:
                raise
            if error.errno == errno.EAGAIN:
                inbox.offer(path)
            else:
                logging.warning("could not mirror %s: %s", path, error)
        except (RuntimeError, subprocess.SubprocessError) as error:
            logging.warning("could not mirror %s: %s", path, error)


def run(args):
    roots = tuple(args.root or (DEFAULT_HOME / "dev", DEFAULT_HOME / "loft", DEFAULT_HOME / ".task"))
    if any(not root.is_absolute() for root in roots) or len({root.stat().st_dev for root in roots}) != 1:
        raise ValueError("mirror sources must be absolute paths on one filesystem")
    drive = Drive(args.mount, args.uuid, args.directory)
    stopped = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stopped.set())
    signal.signal(signal.SIGINT, lambda *_: stopped.set())
    inbox = Inbox(stopped)
    with Fanotify(roots[0]) as reader:
        capture = threading.Thread(target=inbox.capture, args=(reader, roots))
        capture.start()
        reported = False
        try:
            while not stopped.is_set():
                identity = drive.identity()
                if identity is None:
                    if not reported:
                        alert_missing(args.source_user, None if args.no_alert else DEFAULT_NTFY)
                        reported = True
                    stopped.wait(POLL_SECONDS)
                    continue
                reported = False
                try:
                    connect = partial(open_mirror, drive, identity, roots, args.source_user)
                    serve_drive(inbox, drive, identity, connect)
                except OSError as error:
                    if error.errno not in TARGET_IO_ERRORS or drive.identity() == identity:
                        raise
        finally:
            stopped.set()
            capture.join()
        if inbox.error is not None:
            raise RuntimeError("fanotify reader stopped") from inbox.error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mount", type=Path, default=DEFAULT_MOUNT)
    parser.add_argument("--uuid", default=DEFAULT_UUID)
    parser.add_argument("--directory", default="wip")
    parser.add_argument("--root", type=Path, action="append")
    parser.add_argument("--source-user", default="decoder")
    parser.add_argument("--no-alert", action="store_true", help="log locally without sending alerts")
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    run(parser.parse_args())


if __name__ == "__main__":
    main()
