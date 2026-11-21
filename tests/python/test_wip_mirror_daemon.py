"""Exercise queue loss and target replacement through the writer loop."""

import queue
import sys
import threading
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
    inbox = daemon.Inbox(threading.Event())
    inbox.paths = queue.Queue(maxsize=1)
    inbox.offer(tmp_path / "first")
    inbox.offer(tmp_path / "overflow")
    assert inbox.paths.get_nowait() == tmp_path / "first"
    assert inbox.loss.is_set()


def test_loss_during_catch_up_causes_a_rescan_before_event_replay(tmp_path):
    inbox = daemon.Inbox(threading.Event())
    path = tmp_path / "changed"
    inbox.offer(path)
    mirrored = []
    scans = []

    def catch_up():
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
    assert inbox.paths.get_nowait() == path


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
        yield SimpleNamespace(catch_up=lambda: events.append("catch up"), sync=sync)
        events.append("close")

    drive = SimpleNamespace(identity=lambda: 123)
    daemon.serve_drive(inbox, drive, 123, connect)
    assert events == ["open", "catch up", "close", "open", "copy", "close"]


@pytest.mark.parametrize("directory", ["", ".", "..", "../wip", "/wip"])
def test_drive_rejects_a_destination_outside_its_mount(tmp_path, directory):
    with pytest.raises(ValueError, match="single destination directory name"):
        daemon.Drive(tmp_path, daemon.DEFAULT_UUID, directory)
