#!/usr/bin/env python3
"""Keep real-time, versioned copies of serval's work files on its NVMe."""

import argparse
from contextlib import contextmanager, nullcontext
from datetime import datetime
import errno
from functools import partial
import json
import logging
import os
from pathlib import Path
import pwd
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
# Distinct pending paths. A repeat write to a pending path takes no new slot.
QUEUE_LIMIT = 65536
# A database is snapshotted whole. serval's 300M task DB changes every 2 s, so
# each database gets at most one snapshot per interval, and a held change is
# copied when the interval ends.
DATABASE_INTERVAL = 300
DATABASE_SUFFIXES = (".sqlite3", ".db")
# After a clean stop the daemon leaves this list of uncopied paths on the drive,
# and the next start copies those instead of scanning every file (Piotr, 21 Nov:
# the full scan took a core for minutes at every boot). A list written during
# shutdown is honoured on the next boot; the unit stops after user sessions, so
# nothing saved after it. Within one boot it is honoured for RESUME_SECONDS (a
# restart); a crash, lost events or a longer stop means a full scan.
CLEAN_STOP = ".clean-stop"
RESUME_SECONDS = 120
TARGET_IO_ERRORS = {errno.EIO, errno.ENODEV, errno.ENOSPC, errno.EROFS, errno.ESTALE}


class Pacer:
    """Hold repeat copies of a database until its interval has passed."""

    def __init__(self, interval: float = DATABASE_INTERVAL):
        self.interval = interval
        self.last = {}
        self.held = {}

    def admit(self, path: Path, now: float) -> bool:
        name = path.name[:-4] if path.name.endswith("-wal") else path.name
        if not name.endswith(DATABASE_SUFFIXES):
            return True
        database = path.with_name(name)
        due = self.last.get(database, float("-inf")) + self.interval
        if now < due:
            self.held[database] = due
            return False
        self.last[database] = now
        self.held.pop(database, None)
        return True

    def release(self, inbox: "Inbox", now: float):
        for database, due in list(self.held.items()):
            if due <= now:
                del self.held[database]
                inbox.offer(database)


class Stopped(Exception):
    """SIGTERM arrived during a scan."""


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

    def __init__(self, stopped: threading.Event, limit: int = QUEUE_LIMIT):
        self.pending = {}
        self.ready = threading.Condition()
        self.limit = limit
        self.loss = threading.Event()
        # True once a scan finished or a clean-stop list was taken: only then
        # can a stop promise the next start that nothing was missed.
        self.caught_up = False
        self.stopped = stopped
        self.error = None

    def offer(self, path: Path):
        with self.ready:
            if path in self.pending:
                return
            if len(self.pending) >= self.limit:
                self.lose("WIP mirror inbox full")
                return
            self.pending[path] = None
            self.ready.notify()

    def take(self, timeout: float = 0) -> Path | None:
        with self.ready:
            if not self.pending and timeout:
                self.ready.wait(timeout)
            if not self.pending:
                return None
            path = next(iter(self.pending))
            del self.pending[path]
            return path

    def lose(self, reason: str):
        if not self.loss.is_set():
            logging.warning("%s, a rescan follows", reason)
        self.loss.set()

    def capture(self, reader: Fanotify, roots: tuple[Path, ...]):
        try:
            while not self.stopped.is_set():
                ready, _, _ = select.select([reader], [], [], POLL_SECONDS)
                if ready:
                    self.read(reader, roots)
        except Exception as error:
            self.error = error
            self.stopped.set()

    def read(self, reader: Fanotify, roots: tuple[Path, ...]) -> int:
        count = 0
        for event in reader.read():
            count += 1
            if event.mask & OVERFLOW:
                self.lose("fanotify queue overflow")
            elif event.path is not None and in_scope(event.path, roots):
                # Regular CREATE can precede the first write. CLOSE_WRITE
                # copies the finished file, and MOVED_TO handles atomic saves.
                if event.mask & (CLOSE_WRITE | MOVED_TO) or (
                    event.mask & CREATE and event.path.is_symlink()
                ):
                    self.offer(event.path)
        return count


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


def copy(connect, inbox: Inbox, path: Path):
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


def rescan(inbox: Inbox, connect, pacer: Pacer):
    started = time.monotonic()
    inbox.caught_up = False
    with connect() as mirror:
        busy = False

        # Copy the events that arrived so far between scanned entries, so a
        # save does not wait for the whole scan.
        def between():
            nonlocal busy
            if inbox.stopped.is_set():
                # A scan can take minutes; systemd kills a stop after 90 s.
                raise Stopped
            if busy or not inbox.pending:
                return
            busy = True
            try:
                for _ in range(len(inbox.pending)):
                    path = inbox.take()
                    if path is None:
                        break
                    if pacer.admit(path, time.monotonic()):
                        copy(lambda: nullcontext(mirror), inbox, path)
            finally:
                busy = False

        mirror.catch_up(between)
    inbox.caught_up = True
    return time.monotonic() - started


def boot_id() -> str:
    return Path("/proc/sys/kernel/random/boot_id").read_text().strip()


def shutting_down() -> bool:
    result = subprocess.run(["systemctl", "is-system-running"], capture_output=True, text=True, check=False)
    return result.stdout.strip() == "stopping"


def save_clean_stop(target: Path, pending):
    marker = target / CLEAN_STOP
    temporary = target / (CLEAN_STOP + ".tmp")
    with open(temporary, "w", encoding="utf-8") as output:
        json.dump({"boot": boot_id(), "time": time.time(), "shutdown": shutting_down(),
                   "pending": sorted(str(path) for path in pending)}, output)
        output.flush()
        os.fsync(output.fileno())
    os.replace(temporary, marker)


def take_clean_stop(target: Path) -> list[Path] | None:
    """Read and delete the clean-stop list; None means a full scan is needed."""
    marker = target / CLEAN_STOP
    try:
        data = json.loads(marker.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        data = None
    marker.unlink(missing_ok=True)
    if not isinstance(data, dict) or not isinstance(data.get("pending"), list):
        return None
    if data.get("boot") == boot_id():
        if not 0 <= time.time() - float(data.get("time", 0)) <= RESUME_SECONDS:
            return None
    elif data.get("shutdown") is not True:
        return None
    return [Path(path) for path in data["pending"]]


def serve_drive(inbox: Inbox, drive: Drive, identity: int, connect, pacer: Pacer | None = None,
                resume: list[Path] | None = None):
    pacer = pacer or Pacer(DATABASE_INTERVAL)
    if resume is not None and not inbox.loss.is_set():
        logging.info("clean stop before: copying %d pending paths, no full scan", len(resume))
        for path in resume:
            inbox.offer(path)
        inbox.caught_up = True
    else:
        inbox.loss.clear()
        logging.info("catching up WIP mirror")
        logging.info("WIP mirror catch-up complete in %.0f s", rescan(inbox, connect, pacer))
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
            logging.warning("WIP mirror rescan after event loss took %.0f s", rescan(inbox, connect, pacer))
        pacer.release(inbox, now)
        path = inbox.take(POLL_SECONDS)
        if path is None or not pacer.admit(path, time.monotonic()):
            continue
        copy(connect, inbox, path)


def run(args):
    roots = tuple(args.root or (DEFAULT_HOME / "dev", DEFAULT_HOME / "loft", DEFAULT_HOME / ".task"))
    if any(not root.is_absolute() for root in roots) or len({root.stat().st_dev for root in roots}) != 1:
        raise ValueError("mirror sources must be absolute paths on one filesystem")
    drive = Drive(args.mount, args.uuid, args.directory)
    stopped = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stopped.set())
    signal.signal(signal.SIGINT, lambda *_: stopped.set())
    inbox = Inbox(stopped)
    pacer = Pacer(DATABASE_INTERVAL)
    first = True
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
                    resume = None
                    if first:
                        first = False
                        with drive.open(identity) as target:
                            resume = take_clean_stop(target)
                    serve_drive(inbox, drive, identity, connect, pacer, resume)
                except Stopped:
                    break
                except OSError as error:
                    if error.errno not in TARGET_IO_ERRORS or drive.identity() == identity:
                        raise
        finally:
            stopped.set()
            capture.join()
        if inbox.error is not None:
            raise RuntimeError("fanotify reader stopped") from inbox.error
        # Pick up events that arrived while stopping, then leave what is still
        # uncopied for the next start.
        while inbox.read(reader, roots):
            pass
    identity = drive.identity()
    if identity is not None and inbox.caught_up and not inbox.loss.is_set():
        try:
            with drive.open(identity) as target:
                save_clean_stop(target, list(inbox.pending) + list(pacer.held))
        except OSError as error:
            logging.warning("no clean-stop list, the next start scans: %s", error)
            return
        logging.info("clean stop: %d paths left for the next start",
                     len(inbox.pending) + len(pacer.held))


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
