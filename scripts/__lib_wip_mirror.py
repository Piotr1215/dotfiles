"""Copy work files into an append-only, versioned mirror."""

import filecmp
import errno
import logging
import os
from pathlib import Path
import pwd
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import uuid


EXCLUDED = frozenset({
    'node_modules', 'target', '.venv', 'venv', '__pycache__', '.terraform',
    '.cache', 'dist', 'build', '.next', '.tox', '.mypy_cache', '.pytest_cache',
    '.env', '.envrc',
})
DIR_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
SOURCE_RACES = (errno.ENOENT, errno.ENOTDIR, errno.ELOOP)


class MirrorEntryConflict(RuntimeError):
    """The saved path cannot be changed without losing an existing entry."""


class SourceChanged(RuntimeError):
    """A file changed while its contents were being copied."""


class SourceSnapshotError(RuntimeError):
    """SQLite could not read a consistent source snapshot."""

# SQLite reads user-controlled pages, extensions and WAL files. Run it with the
# source user's permissions and send the resulting database to the parent.
SQLITE_SNAPSHOT = r'''
import pathlib, shutil, sqlite3, sys, tempfile
source = pathlib.Path(sys.argv[1])
try:
    with tempfile.TemporaryDirectory(prefix='wip-sqlite-') as directory:
        destination = pathlib.Path(directory) / 'snapshot.sqlite3'
        with sqlite3.connect(source.as_uri() + '?mode=ro', uri=True) as src:
            with sqlite3.connect(destination) as dst:
                src.backup(dst)
        with destination.open('rb') as snapshot:
            shutil.copyfileobj(snapshot, sys.stdout.buffer)
except sqlite3.Error as error:
    print(f'SQLite snapshot failed: {error}', file=sys.stderr)
    code = getattr(error, 'sqlite_errorcode', 0) & 0xff
    sys.exit(21 if code in (sqlite3.SQLITE_IOERR, sqlite3.SQLITE_FULL, sqlite3.SQLITE_NOMEM) else 20)
'''


def _mounts():
    """Read mount points so bind mounts on the same device are skipped too."""
    points = set()
    with open('/proc/self/mountinfo', encoding='utf-8') as stream:
        for line in stream:
            mount = line.split()[4]
            for escaped, character in (('\\040', ' '), ('\\011', '\t'),
                                       ('\\012', '\n'), ('\\134', '\\')):
                mount = mount.replace(escaped, character)
            points.add(Path(mount))
    return points


def _open_absolute_directory(path):
    """Open each source directory without following a substituted symlink."""
    descriptor = os.open('/', DIR_FLAGS)
    try:
        for part in path.parts[1:]:
            child = os.open(part, DIR_FLAGS, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = child
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def _check_directory(path):
    info = path.lstat()
    if (not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid()
            or info.st_mode & 0o022):
        raise MirrorEntryConflict(f'unsafe mirror directory: {path}')


def _same_source(first, second):
    return (first.st_dev, first.st_ino, first.st_size, first.st_mtime_ns, first.st_ctime_ns) == (
        second.st_dev, second.st_ino, second.st_size, second.st_mtime_ns, second.st_ctime_ns
    )


class Mirror:
    def __init__(self, target: Path, roots: tuple[Path, ...], *,
                 source_user: str | None = None, reflink: bool = True):
        self.target = Path(target)
        self.roots = tuple(Path(os.path.abspath(root)) for root in roots)
        self.source_user = source_user
        self.reflink = reflink
        self._catching_up = False
        self._skipped = 0
        if not self.target.is_dir() or not self.roots:
            raise ValueError('target must exist and roots must be nonempty')
        target_info = self.target.stat()
        if target_info.st_uid != os.geteuid() or target_info.st_mode & 0o022:
            raise ValueError('target must be owned by the mirror user and not writable by others')
        if os.geteuid() == 0 and source_user is None:
            raise ValueError('source_user is required when running as root')
        if source_user is not None:
            account = pwd.getpwnam(source_user)
            if os.geteuid() not in (0, account.pw_uid):
                raise PermissionError('cannot switch to source user')

    def catch_up(self):
        self._catching_up = True
        self._skipped = 0
        try:
            for root in self.roots:
                self.sync(root)
        finally:
            self._catching_up = False
            if self._skipped:
                logging.warning('wip mirror catch-up skipped %d entries', self._skipped)

    def _skip(self, path, error):
        if not self._catching_up:
            logging.warning('wip mirror skipped %s: %s', path, error)
            return
        self._skipped += 1
        if self._skipped <= 20:
            logging.warning('wip mirror skipped %s: %s', path, error)

    def _source_call(self, path, operation, *args, **kwargs):
        try:
            return operation(*args, **kwargs)
        except OSError as error:
            if error.errno not in SOURCE_RACES:
                raise
            self._skip(path, error)
            return None

    def sync(self, path: Path):
        path = Path(os.path.abspath(path))
        # A WAL write changes the database even when its main file stays still.
        if path.name.endswith(('.sqlite3-wal', '.db-wal')):
            path = path.with_name(path.name[:-4])
        if path.name.endswith(('.sqlite3-shm', '.db-shm', '.sqlite3-journal', '.db-journal')):
            return
        root = next((item for item in self.roots if path == item or item in path.parents), None)
        if root is None or any(part in EXCLUDED for part in path.relative_to(root).parts):
            return
        mounts = _mounts()
        if any(point != root and (point == path or point in path.parents)
               and (point == root or root in point.parents) for point in mounts):
            return
        descriptor = self._source_call(root, _open_absolute_directory, root)
        if descriptor is None:
            return
        try:
            parts = path.relative_to(root).parts
            if not parts:
                self._directory(descriptor, root, mounts)
                return
            for part in parts[:-1]:
                child = self._source_call(path, os.open, part, DIR_FLAGS, dir_fd=descriptor)
                if child is None:
                    return
                os.close(descriptor)
                descriptor = child
            self._entry(descriptor, parts[-1], path, mounts)
        finally:
            os.close(descriptor)

    def _directory(self, descriptor, path, mounts):
        with os.scandir(descriptor) as entries:
            for entry in entries:
                if entry.name not in EXCLUDED:
                    try:
                        self._entry(descriptor, entry.name, path / entry.name, mounts)
                    except (MirrorEntryConflict, SourceChanged, SourceSnapshotError) as error:
                        if not self._catching_up:
                            raise
                        self._skip(path / entry.name, error)

    def _entry(self, parent_fd, name, path, mounts):
        if path in mounts:
            return
        info = self._source_call(path, os.stat, name, dir_fd=parent_fd, follow_symlinks=False)
        if info is None:
            return
        try:
            if stat.S_ISDIR(info.st_mode):
                child = self._source_call(path, os.open, name, DIR_FLAGS, dir_fd=parent_fd)
                if child is None:
                    return
                try:
                    opened = os.fstat(child)
                    if (info.st_dev, info.st_ino) != (opened.st_dev, opened.st_ino):
                        self._skip(path, 'directory changed during open')
                        return
                    self._directory(child, path, mounts)
                finally:
                    os.close(child)
            elif stat.S_ISLNK(info.st_mode):
                value = self._source_call(path, os.readlink, name, dir_fd=parent_fd)
                if value is not None:
                    self._symlink(path, value)
            elif stat.S_ISREG(info.st_mode):
                if name.endswith(('.sqlite3-wal', '.db-wal', '.sqlite3-shm', '.db-shm',
                                  '.sqlite3-journal', '.db-journal')):
                    return
                fd = self._source_call(path, os.open, name,
                                       os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC,
                                       dir_fd=parent_fd)
                if fd is None:
                    return
                try:
                    current = os.fstat(fd)
                    if not stat.S_ISREG(current.st_mode) or not _same_source(info, current):
                        self._skip(path, 'file changed during open')
                        return
                    self._file(path, fd, current)
                finally:
                    os.close(fd)
        except MirrorEntryConflict:
            raise

    def _destination(self, category, path):
        # The target is a trusted root-owned directory, anchored by its caller.
        destination = self.target / category
        _check_directory(destination)
        for part in path.parts[1:-1]:
            destination = destination / part
            try:
                destination.mkdir(mode=0o755)
            except FileExistsError:
                pass
            _check_directory(destination)
        return destination / path.name

    def _version(self, destination, path):
        if not destination.exists() and not destination.is_symlink():
            return
        info = destination.lstat()
        if info.st_uid != os.geteuid() or (not stat.S_ISLNK(info.st_mode) and info.st_mode & 0o022):
            raise MirrorEntryConflict(f'unsafe mirror entry: {destination}')
        version = self._destination('versions', path)
        version = version.with_name(f'{version.name}@{time.time_ns()}-{uuid.uuid4().hex}')
        if stat.S_ISLNK(info.st_mode):
            version.symlink_to(os.readlink(destination))
        elif stat.S_ISREG(info.st_mode):
            temporary = version.with_name('.wip-' + uuid.uuid4().hex)
            try:
                if self.reflink:
                    parts = self.target.parts
                    inherited = ()
                    if len(parts) >= 5 and parts[1:4] == ('proc', 'self', 'fd'):
                        inherited = (int(parts[4]),)
                    subprocess.run(['cp', '--reflink=always', '--preserve=mode,timestamps',
                                    '--', str(destination), str(temporary)], check=True,
                                   pass_fds=inherited)
                else:
                    shutil.copy2(destination, temporary, follow_symlinks=False)
                os.replace(temporary, version)
            finally:
                temporary.unlink(missing_ok=True)
        else:
            raise MirrorEntryConflict(f'unsafe mirror entry: {destination}')

    def _symlink(self, path, value):
        destination = self._destination('live', path)
        if destination.is_symlink() and os.readlink(destination) == value:
            return
        temporary = destination.with_name('.wip-' + uuid.uuid4().hex)
        try:
            temporary.symlink_to(value)
            self._version(destination, path)
            os.replace(temporary, destination)
        finally:
            temporary.unlink(missing_ok=True)

    def _file(self, path, fd, info):
        destination = self._destination('live', path)
        mode = stat.S_IMODE(info.st_mode) & 0o755
        sqlite = path.suffix in ('.sqlite3', '.db') and os.pread(fd, 16, 0) == b'SQLite format 3\0'
        if not sqlite and self._unchanged(fd, info, destination, mode):
            return
        with tempfile.NamedTemporaryFile(prefix='.wip-', dir=destination.parent, delete=False) as output:
            temporary = Path(output.name)
            try:
                if sqlite:
                    kwargs = {}
                    if self.source_user is not None and os.geteuid() == 0:
                        account = pwd.getpwnam(self.source_user)
                        kwargs.update(user=account.pw_uid, group=account.pw_gid, extra_groups=[])
                    try:
                        subprocess.run([sys.executable, '-I', '-c', SQLITE_SNAPSHOT, str(path)],
                                       stdout=output, check=True, **kwargs)
                    except subprocess.CalledProcessError as error:
                        if error.returncode == 20:
                            raise SourceSnapshotError(f'SQLite snapshot failed: {path}') from error
                        raise
                else:
                    with os.fdopen(os.dup(fd), 'rb') as source:
                        shutil.copyfileobj(source, output)
                    if not _same_source(info, os.fstat(fd)):
                        raise SourceChanged(f'source changed during copy: {path}')
                output.flush()
                os.fchmod(output.fileno(), mode)
                os.utime(output.fileno(), ns=(info.st_atime_ns, info.st_mtime_ns))
                if (destination.is_file() and not destination.is_symlink()
                        and filecmp.cmp(temporary, destination, shallow=False)
                        and stat.S_IMODE(destination.stat().st_mode) == mode
                        and destination.stat().st_mtime_ns == info.st_mtime_ns):
                    return
                self._version(destination, path)
                os.replace(temporary, destination)
            finally:
                temporary.unlink(missing_ok=True)

    def _unchanged(self, source_fd, info, destination, mode):
        try:
            destination_fd = os.open(destination, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        except FileNotFoundError:
            return False
        except OSError:
            if destination.is_symlink():
                return False
            raise
        try:
            saved = os.fstat(destination_fd)
            if (not stat.S_ISREG(saved.st_mode) or saved.st_uid != os.geteuid()
                    or saved.st_mode & 0o022):
                raise MirrorEntryConflict(f'unsafe mirror entry: {destination}')
            if (saved.st_size, saved.st_mtime_ns, stat.S_IMODE(saved.st_mode)) != (
                    info.st_size, info.st_mtime_ns, mode):
                return False
            while True:
                source_chunk = os.read(source_fd, 1024 * 1024)
                if source_chunk != os.read(destination_fd, 1024 * 1024):
                    return False
                if not source_chunk:
                    return _same_source(info, os.fstat(source_fd))
        finally:
            os.lseek(source_fd, 0, os.SEEK_SET)
            os.close(destination_fd)
