"""Checks for the mixed fanotify event stream the mirror consumes."""

import errno
import os
import sys
from pathlib import Path
from unittest.mock import Mock

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
import __lib_wip_fanotify as fanotify


def event(mask, info=b""):
    size = fanotify.METADATA.size
    return fanotify.METADATA.pack(
        size + len(info), fanotify.FANOTIFY_METADATA_VERSION, 0, size, mask, -1, 42,
    ) + info


def info_record(name):
    handle = fanotify.HANDLE_HEADER.pack(4, 1) + b"abcd"
    body = bytes(fanotify.FSID_SIZE) + handle + name + b"\0"
    header = fanotify.INFO_HEADER.pack(
        fanotify.FAN_EVENT_INFO_TYPE_DFID_NAME, 0, fanotify.INFO_HEADER.size + len(body),
    )
    return header + body, handle


def test_reads_mixed_masks_without_splitting_valid_filename_bytes():
    info, handle = info_record(b"with\nspace \xff")
    buffer = event(fanotify.CLOSE_WRITE | fanotify.CREATE, info)
    buffer += event(fanotify.OVERFLOW)
    buffer += event(fanotify.MOVED_TO, info)
    assert list(fanotify.records(buffer)) == [
        (fanotify.CLOSE_WRITE | fanotify.CREATE, handle, b"with\nspace \xff"),
        (fanotify.OVERFLOW, b"", b""),
        (fanotify.MOVED_TO, handle, b"with\nspace \xff"),
    ]


@pytest.mark.parametrize("name", [b"../other", b"absolute/file", b"..", b""])
def test_rejects_paths_in_place_of_fanotify_entry_names(name):
    info, _ = info_record(name)
    with pytest.raises(ValueError, match="invalid fanotify entry name"):
        list(fanotify.records(event(fanotify.MOVED_TO, info)))


def test_rejects_truncated_record():
    info, _ = info_record(b"name")
    with pytest.raises(ValueError, match="metadata"):
        list(fanotify.records(event(fanotify.CREATE, info)[:-1]))


def test_transient_handle_failure_requests_catch_up_and_keeps_reading(monkeypatch, tmp_path):
    reader = fanotify.Fanotify.__new__(fanotify.Fanotify)
    reader.fd = 42
    reader.resolve_directory = Mock(side_effect=[OSError(errno.ENOMEM, "memory"), tmp_path])
    info, _ = info_record(b"changed")
    monkeypatch.setattr(fanotify.os, "read", lambda *_: event(fanotify.CLOSE_WRITE, info) * 2)

    assert list(reader.read()) == [
        fanotify.Event(fanotify.OVERFLOW),
        fanotify.Event(fanotify.CLOSE_WRITE, tmp_path / "changed"),
    ]


def test_the_event_queue_is_unlimited(tmp_path, monkeypatch):
    # A capped daemon falls behind in a burst; a bounded queue then overflows.
    libc = Mock()
    libc.fanotify_init.return_value = os.open(tmp_path, os.O_RDONLY)
    libc.fanotify_mark.return_value = 0
    monkeypatch.setattr(fanotify.ctypes, "CDLL", lambda *a, **k: libc)
    with fanotify.Fanotify(tmp_path):
        pass
    flags = libc.fanotify_init.call_args.args[0]
    assert flags & fanotify.FAN_UNLIMITED_QUEUE
    assert flags & fanotify.FAN_REPORT_DFID_NAME
