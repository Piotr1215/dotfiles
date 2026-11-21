"""Read filesystem-wide fanotify events, including the kernel loss marker."""

import ctypes
import errno
import os
import struct
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path

# Linux UAPI, <linux/fanotify.h>.
CLOSE_WRITE = 0x00000008
MOVED_TO = 0x00000080
CREATE = 0x00000100
OVERFLOW = 0x00004000
ON_DIRECTORY = 0x40000000

FAN_CLOEXEC = 0x00000001
FAN_NONBLOCK = 0x00000002
# The default queue holds 16384 events. The daemon runs under a CPU quota, so
# a burst outran its reader, the queue overflowed and each overflow forced a
# full rescan (21 Nov). Unlimited costs kernel memory during a burst, not events.
FAN_UNLIMITED_QUEUE = 0x00000010
FAN_REPORT_DFID_NAME = 0x00000C00
FAN_MARK_ADD_FILESYSTEM = 0x00000101
FANOTIFY_METADATA_VERSION = 3
FAN_EVENT_INFO_TYPE_DFID_NAME = 2

METADATA = struct.Struct("=IBBHQii")
INFO_HEADER = struct.Struct("=BBH")
HANDLE_HEADER = struct.Struct("=Ii")
FSID_SIZE = 8


@dataclass(frozen=True)
class Event:
    mask: int
    path: Path | None = None


def records(buffer: bytes) -> Iterator[tuple[int, bytes, bytes]]:
    """Yield each event's mask, directory file handle, and entry name."""
    offset = 0
    while offset < len(buffer):
        if len(buffer) - offset < METADATA.size:
            raise ValueError("truncated fanotify event metadata")
        size, version, _, metadata_size, mask, _, _ = METADATA.unpack_from(buffer, offset)
        end = offset + size
        if (version != FANOTIFY_METADATA_VERSION
                or not METADATA.size <= metadata_size <= size or end > len(buffer)):
            raise ValueError("invalid fanotify event metadata")
        if mask & OVERFLOW:
            yield mask, b"", b""
        else:
            for handle, name in directory_entries(buffer, offset + metadata_size, end):
                yield mask, handle, name
        offset = end


def directory_entries(buffer: bytes, offset: int, end: int) -> Iterator[tuple[bytes, bytes]]:
    while offset < end:
        if end - offset < INFO_HEADER.size:
            raise ValueError("truncated fanotify information record")
        kind, _, size = INFO_HEADER.unpack_from(buffer, offset)
        next_offset = offset + size
        if size < INFO_HEADER.size or next_offset > end:
            raise ValueError("invalid fanotify information record")
        if kind == FAN_EVENT_INFO_TYPE_DFID_NAME:
            handle_start = offset + INFO_HEADER.size + FSID_SIZE
            if handle_start + HANDLE_HEADER.size >= next_offset:
                raise ValueError("truncated fanotify file handle")
            handle_size, _ = HANDLE_HEADER.unpack_from(buffer, handle_start)
            name_start = handle_start + HANDLE_HEADER.size + handle_size
            name, delimiter, _ = buffer[name_start:next_offset].partition(b"\0")
            if not handle_size or not delimiter or not name or b"/" in name or name == b"..":
                raise ValueError("invalid fanotify entry name")
            yield buffer[handle_start:name_start], name
        offset = next_offset


def checked_fd(result: int) -> int:
    if result < 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error))
    return result


class Fanotify:
    """One filesystem mark, with names resolved through their parent handles."""

    def __init__(self, filesystem: Path):
        self.libc = ctypes.CDLL(None, use_errno=True)
        self.libc.fanotify_init.argtypes = (ctypes.c_uint, ctypes.c_uint)
        self.libc.fanotify_mark.argtypes = (
            ctypes.c_int, ctypes.c_uint, ctypes.c_uint64, ctypes.c_int, ctypes.c_char_p,
        )
        self.libc.open_by_handle_at.argtypes = (ctypes.c_int, ctypes.c_char_p, ctypes.c_int)
        self.mount_fd = os.open(filesystem, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
        try:
            self.fd = checked_fd(self.libc.fanotify_init(
                FAN_CLOEXEC | FAN_NONBLOCK | FAN_UNLIMITED_QUEUE | FAN_REPORT_DFID_NAME, os.O_RDONLY,
            ))
            try:
                checked_fd(self.libc.fanotify_mark(
                    self.fd,
                    FAN_MARK_ADD_FILESYSTEM,
                    CLOSE_WRITE | MOVED_TO | CREATE | ON_DIRECTORY,
                    self.mount_fd,
                    b".",
                ))
            except BaseException:
                os.close(self.fd)
                raise
        except BaseException:
            os.close(self.mount_fd)
            raise

    def __enter__(self):
        return self

    def __exit__(self, *_):
        os.close(self.fd)
        os.close(self.mount_fd)

    def fileno(self) -> int:
        return self.fd

    def read(self) -> Iterator[Event]:
        try:
            buffer = os.read(self.fd, 64 * 1024)
        except BlockingIOError:
            return
        for mask, handle, name in records(buffer):
            if mask & OVERFLOW:
                yield Event(mask)
                continue
            try:
                directory = self.resolve_directory(handle)
            except OSError as error:
                if error.errno not in (errno.EAGAIN, errno.ENOMEM):
                    raise
                # A transient handle resolution failure drops a notification
                # just like overflow. Reconcile the files instead of exiting.
                yield Event(OVERFLOW)
                continue
            if directory is not None:
                yield Event(mask, directory / os.fsdecode(name))

    def resolve_directory(self, handle: bytes) -> Path | None:
        try:
            directory_fd = checked_fd(self.libc.open_by_handle_at(
                self.mount_fd, handle, os.O_PATH | os.O_DIRECTORY | os.O_CLOEXEC,
            ))
        except OSError as error:
            if error.errno in (errno.ESTALE, errno.ENOENT):
                return None
            raise
        try:
            # Resolve the parent from its open descriptor so a rename cannot
            # produce a path through a replacement symlink.
            if os.fstat(directory_fd).st_nlink == 0:
                return None
            return Path(os.readlink(f"/proc/self/fd/{directory_fd}"))
        finally:
            os.close(directory_fd)
