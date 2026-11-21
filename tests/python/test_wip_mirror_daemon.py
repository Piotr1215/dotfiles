"""Exercise queue loss and target replacement through the writer loop."""

import argparse
import json
import os
import signal
import sys
import threading
import time
from contextlib import contextmanager, nullcontext
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
import __wip_mirror as daemon


def test_scope_checks_directory_boundaries_and_exclusions(tmp_path):
    root = tmp_path / "dev"
    assert daemon.in_scope(root / "project/.git/logs/HEAD", (root,))
    assert not daemon.in_scope(tmp_path / "dev-other/file", (root,))
    assert not daemon.in_scope(root / "project/node_modules/file", (root,))
    assert not daemon.in_scope(root / "project/.envrc", (root,))


def test_user_space_queue_loss_requests_catch_up(tmp_path):
    inbox = daemon.Inbox(threading.Event(), limit=1)
    inbox.offer(tmp_path / "first")
    inbox.offer(tmp_path / "first")
    assert not inbox.loss.is_set()
    inbox.offer(tmp_path / "overflow")
    assert inbox.take() == tmp_path / "first"
    assert inbox.take() is None
    assert inbox.loss.is_set()


def test_loss_during_catch_up_causes_a_rescan_before_event_replay(tmp_path):
    inbox = daemon.Inbox(threading.Event())
    path = tmp_path / "changed"
    inbox.offer(path)
    mirrored = []
    scans = []

    def catch_up(between=None):
        scans.append(True)
        if len(scans) == 1:
            inbox.loss.set()

    def sync(actual):
        mirrored.append(actual)
        inbox.stopped.set()

    drive = SimpleNamespace(identity=lambda: 123)
    mirror = SimpleNamespace(catch_up=catch_up, sync=sync)
    daemon.serve_drive(inbox, drive, 123, lambda: nullcontext(mirror))

    assert len(scans) == 2
    assert mirrored == [path]


def test_drive_replacement_preserves_events_for_new_mount(tmp_path):
    inbox = daemon.Inbox(threading.Event())
    path = tmp_path / "new"
    inbox.offer(path)
    drive = SimpleNamespace(identity=lambda: 456)
    mirror = Mock()
    daemon.serve_drive(inbox, drive, 123, lambda: nullcontext(mirror))

    mirror.sync.assert_not_called()
    assert inbox.take() == path


def test_target_is_closed_between_catch_up_and_live_copy(tmp_path):
    inbox = daemon.Inbox(threading.Event())
    inbox.offer(tmp_path / "file")
    events = []

    def sync(_):
        events.append("copy")
        inbox.stopped.set()

    @contextmanager
    def connect():
        events.append("open")
        yield SimpleNamespace(catch_up=lambda between=None: events.append("catch up"), sync=sync)
        events.append("close")

    drive = SimpleNamespace(identity=lambda: 123)
    daemon.serve_drive(inbox, drive, 123, connect)
    assert events == ["open", "catch up", "close", "open", "copy", "close"]



def test_events_are_copied_between_entries_of_a_rescan(tmp_path):
    inbox = daemon.Inbox(threading.Event())
    events = []

    def catch_up(between=None):
        events.append("scan start")
        inbox.offer(tmp_path / "saved")
        between()
        events.append("scan end")
        inbox.stopped.set()

    drive = SimpleNamespace(identity=lambda: 123)
    mirror = SimpleNamespace(catch_up=catch_up, sync=lambda path: events.append(f"copy {path.name}"))
    daemon.serve_drive(inbox, drive, 123, lambda: nullcontext(mirror))
    assert events == ["scan start", "copy saved", "scan end"]


def test_a_stop_ends_a_scan_at_the_next_entry(tmp_path):
    inbox = daemon.Inbox(threading.Event())
    scanned = []

    def catch_up(between=None):
        for name in ("one", "two", "three"):
            scanned.append(name)
            if name == "one":
                inbox.stopped.set()
            between()

    drive = SimpleNamespace(identity=lambda: 123)
    mirror = SimpleNamespace(catch_up=catch_up, sync=Mock())
    with pytest.raises(daemon.Stopped):
        daemon.serve_drive(inbox, drive, 123, lambda: nullcontext(mirror))
    assert scanned == ["one"]


def test_a_busy_database_is_copied_once_per_interval(tmp_path):
    inbox = daemon.Inbox(threading.Event())
    pacer = daemon.Pacer(interval=300)
    database = tmp_path / "taskchampion.sqlite3"
    assert pacer.admit(database, 1000)
    assert not pacer.admit(tmp_path / "taskchampion.sqlite3-wal", 1002)
    assert pacer.admit(tmp_path / "notes.md", 1003)
    pacer.release(inbox, 1299)
    assert inbox.take() is None
    pacer.release(inbox, 1300)
    assert inbox.take() == database
    assert pacer.admit(database, 1300)
    assert not pacer.held


def test_the_writer_holds_a_repeat_database_event_until_its_interval(tmp_path, monkeypatch):
    monkeypatch.setattr(daemon, "POLL_SECONDS", 0.01)
    monkeypatch.setattr(daemon, "DATABASE_INTERVAL", 0.05)
    inbox = daemon.Inbox(threading.Event())
    for name in ("work.db", "work.db-wal", "notes.md"):
        inbox.offer(tmp_path / name)
    probes = iter([123] * 50)
    drive = SimpleNamespace(identity=lambda: next(probes, 456))
    copied = []
    mirror = SimpleNamespace(catch_up=lambda between=None: None, sync=copied.append)
    daemon.serve_drive(inbox, drive, 123, lambda: nullcontext(mirror))
    assert copied == [tmp_path / "work.db", tmp_path / "notes.md", tmp_path / "work.db"]


def test_a_clean_stop_list_is_used_once_after_a_shutdown_or_a_quick_restart(tmp_path, monkeypatch):
    monkeypatch.setattr(daemon, "boot_id", lambda: "boot-1")
    monkeypatch.setattr(daemon, "shutting_down", lambda: False)
    daemon.save_clean_stop(tmp_path, [tmp_path / "b", tmp_path / "a"])
    assert daemon.take_clean_stop(tmp_path) == [tmp_path / "a", tmp_path / "b"]
    assert daemon.take_clean_stop(tmp_path) is None
    monkeypatch.setattr(daemon, "shutting_down", lambda: True)
    daemon.save_clean_stop(tmp_path, [])
    monkeypatch.setattr(daemon, "boot_id", lambda: "boot-2")
    assert daemon.take_clean_stop(tmp_path) == []


def test_a_stop_without_shutdown_means_a_scan_on_the_next_boot(tmp_path, monkeypatch):
    # Stopped by hand, files kept changing, then a reboot: the list misses them.
    monkeypatch.setattr(daemon, "boot_id", lambda: "boot-1")
    monkeypatch.setattr(daemon, "shutting_down", lambda: False)
    daemon.save_clean_stop(tmp_path, [])
    monkeypatch.setattr(daemon, "boot_id", lambda: "boot-2")
    assert daemon.take_clean_stop(tmp_path) is None


def test_a_stale_or_broken_clean_stop_list_means_a_full_scan(tmp_path, monkeypatch):
    monkeypatch.setattr(daemon, "boot_id", lambda: "boot-1")
    (tmp_path / daemon.CLEAN_STOP).write_text(json.dumps(
        {"boot": "boot-1", "time": time.time() - daemon.RESUME_SECONDS - 5, "pending": []}))
    assert daemon.take_clean_stop(tmp_path) is None
    (tmp_path / daemon.CLEAN_STOP).write_text("{not json")
    assert daemon.take_clean_stop(tmp_path) is None
    assert not (tmp_path / daemon.CLEAN_STOP).exists()


def test_resume_copies_the_list_without_a_scan_unless_events_were_lost(tmp_path):
    for lost in (False, True):
        inbox = daemon.Inbox(threading.Event())
        if lost:
            inbox.loss.set()
        events = []

        def catch_up(between=None):
            events.append("scan")
            inbox.stopped.set()

        def sync(path):
            events.append(path.name)
            inbox.stopped.set()

        drive = SimpleNamespace(identity=lambda: 123)
        mirror = SimpleNamespace(catch_up=catch_up, sync=sync)
        daemon.serve_drive(inbox, drive, 123, lambda: nullcontext(mirror), resume=[tmp_path / "pending.md"])
        assert events == (["scan"] if lost else ["pending.md"])


def test_a_stopped_daemon_leaves_its_list_and_the_next_start_skips_the_scan(tmp_path, monkeypatch, caplog):
    root = tmp_path / "dev"
    root.mkdir()
    (root / "notes.md").write_text("first")
    (root / "late.md").write_text("saved while stopping")
    target = tmp_path / "drive" / "wip"
    for name in ("live", "versions"):
        (target / name).mkdir(parents=True, mode=0o755)
        (target / name).chmod(0o755)
    target.chmod(0o755)
    monkeypatch.setattr(daemon, "POLL_SECONDS", 0.05)
    monkeypatch.setattr(daemon, "boot_id", lambda: "boot-1")
    monkeypatch.setattr(daemon, "shutting_down", lambda: False)

    class Reader:
        def __init__(self, _root):
            self.r, self.w = os.pipe()

        def __enter__(self):
            return self

        def __exit__(self, *_):
            os.close(self.r)
            os.close(self.w)

        def fileno(self):
            return self.r

        def read(self):
            # One save arrives while the daemon stops: only the final drain sees it.
            late, self.late = getattr(self, "late", True), False
            return iter([SimpleNamespace(mask=daemon.CLOSE_WRITE, path=root / "late.md")] if late else [])

    @contextmanager
    def opened(_identity):
        yield target

    drive = SimpleNamespace(identity=lambda: 1, open=opened)
    monkeypatch.setattr(daemon, "Fanotify", Reader)
    monkeypatch.setattr(daemon, "Drive", lambda *_: drive)
    args = argparse.Namespace(root=[root], mount=tmp_path / "drive", uuid=daemon.DEFAULT_UUID,
                              directory="wip", source_user=None, no_alert=True)
    previous = signal.getsignal(signal.SIGTERM)
    try:
        for expected in ("catch-up complete", "no full scan"):
            caplog.clear()
            with caplog.at_level("INFO"):
                threading.Timer(0.4, os.kill, (os.getpid(), signal.SIGTERM)).start()
                daemon.run(args)
            assert any(expected in line for line in caplog.messages)
            assert str(root / "late.md") in json.loads((target / daemon.CLEAN_STOP).read_text())["pending"]
    finally:
        signal.signal(signal.SIGTERM, previous)
    assert (target / "live" / str(root / "notes.md").lstrip("/")).read_text() == "first"
    assert (target / "live" / str(root / "late.md").lstrip("/")).read_text() == "saved while stopping"

@pytest.mark.parametrize("directory", ["", ".", "..", "../wip", "/wip"])
def test_drive_rejects_a_destination_outside_its_mount(tmp_path, directory):
    with pytest.raises(ValueError, match="single destination directory name"):
        daemon.Drive(tmp_path, daemon.DEFAULT_UUID, directory)
