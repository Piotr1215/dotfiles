import importlib.util
import os
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location(
    'wip_storage', Path(__file__).resolve().parents[2] / 'scripts/__lib_wip_mirror.py'
)
storage = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(storage)


class MirrorStorageTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.base = Path(self.directory.name)
        self.root = self.base / 'source'
        self.root.mkdir()
        self.target = self.base / 'target'
        (self.target / 'live').mkdir(parents=True)
        (self.target / 'versions').mkdir()
        self.target.chmod(0o755)
        (self.target / 'live').chmod(0o755)
        (self.target / 'versions').chmod(0o755)
        self.mirror = storage.Mirror(self.target, (self.root,), reflink=False)

    def mirrored(self, name):
        return self.target / 'live' / str((self.root / name)).lstrip('/')

    def versions(self, name):
        return sorted((self.target / 'versions' / str(self.root).lstrip('/')).glob(name + '@*'))

    def test_replacement_retains_previous_content_and_delete_is_ignored(self):
        source = self.root / 'file'
        source.write_text('first')
        source.chmod(0o640)
        self.mirror.sync(source)
        self.assertEqual(self.mirrored('file').read_text(), 'first')
        self.assertEqual(self.mirrored('file').stat().st_mode & 0o777, 0o640)
        self.mirror.sync(source)
        self.assertEqual(self.versions('file'), [])
        source.write_text('second')
        self.mirror.sync(source)
        self.assertEqual(self.mirrored('file').read_text(), 'second')
        self.assertEqual([p.read_text() for p in self.versions('file')], ['first'])
        source.unlink()
        self.mirror.sync(source)
        self.assertEqual(self.mirrored('file').read_text(), 'second')

    def test_unchanged_file_does_not_stage_a_copy(self):
        source = self.root / 'file'
        source.write_text('same')
        self.mirror.sync(source)
        with patch.object(storage.tempfile, 'NamedTemporaryFile', side_effect=AssertionError('staged')):
            self.mirror.sync(source)

    def test_special_and_public_write_bits_are_removed(self):
        source = self.root / 'file'
        source.write_text('data')
        source.chmod(0o7777)
        self.mirror.sync(source)
        self.assertEqual(self.mirrored('file').stat().st_mode & 0o7777, 0o755)

    def test_writable_mirror_directory_is_rejected(self):
        source = self.root / 'file'
        source.write_text('data')
        (self.target / 'live').chmod(0o777)
        with self.assertRaises(RuntimeError):
            self.mirror.sync(source)

    def test_catch_up_and_directory_events_apply_same_exclusions(self):
        (self.root / 'dir').mkdir()
        (self.root / 'dir' / 'work').write_text('keep')
        (self.root / 'dir' / '.env').write_text('secret')
        (self.root / 'dir' / 'node_modules').mkdir()
        (self.root / 'dir' / 'node_modules' / 'data').write_text('skip')
        self.mirror.catch_up()
        self.assertEqual(self.mirrored('dir/work').read_text(), 'keep')
        self.assertFalse(self.mirrored('dir/.env').exists())
        self.assertFalse(self.mirrored('dir/node_modules').exists())
        self.mirror.sync(self.root / 'dir' / '.env')
        self.assertFalse(self.mirrored('dir/.env').exists())

    def test_symlinks_are_preserved_but_never_followed(self):
        outside = self.base / 'outside'
        outside.mkdir()
        (outside / 'secret').write_text('outside')
        (self.root / 'link').symlink_to(outside, target_is_directory=True)
        self.mirror.catch_up()
        self.assertTrue(self.mirrored('link').is_symlink())
        self.assertEqual(os.readlink(self.mirrored('link')), str(outside))
        self.mirror.sync(self.root / 'link' / 'secret')
        self.assertEqual((outside / 'secret').read_text(), 'outside')

    def test_destination_symlink_ancestor_is_rejected(self):
        (self.root / 'dir').mkdir()
        (self.root / 'dir' / 'file').write_text('data')
        mirror_parent = self.mirrored('dir').parent
        mirror_parent.mkdir(parents=True)
        self.mirrored('dir').symlink_to(self.base, target_is_directory=True)
        with self.assertRaises(RuntimeError):
            self.mirror.sync(self.root / 'dir' / 'file')
        self.assertFalse((self.base / 'file').exists())

    def test_wal_event_takes_consistent_database_snapshot(self):
        source = self.root / 'work.sqlite3'
        with sqlite3.connect(source) as db:
            db.execute('PRAGMA journal_mode=WAL')
            db.execute('CREATE TABLE records (value TEXT)')
            db.execute("INSERT INTO records VALUES ('first')")
            db.commit()
            self.mirror.sync(source)
            db.execute("INSERT INTO records VALUES ('second')")
            db.commit()
            self.mirror.sync(Path(str(source) + '-wal'))
            with sqlite3.connect(self.mirrored('work.sqlite3').as_uri() + '?mode=ro&immutable=1', uri=True) as copy:
                self.assertEqual(copy.execute('SELECT value FROM records ORDER BY rowid').fetchall(),
                                 [('first',), ('second',)])
                self.assertEqual(copy.execute('PRAGMA integrity_check').fetchone()[0], 'ok')
            self.assertEqual(len(self.versions('work.sqlite3')), 1)
            self.assertFalse(self.mirrored('work.sqlite3-wal').exists())

    def test_scope_and_special_files_are_ignored(self):
        external = self.base / 'external'
        external.write_text('outside')
        os.mkfifo(self.root / 'fifo')
        self.mirror.sync(external)
        self.mirror.catch_up()
        self.assertFalse(self.mirrored('fifo').exists())
        self.assertFalse((self.target / 'live' / str(external).lstrip('/')).exists())

    def test_rename_preserves_both_names(self):
        source = self.root / 'old'
        source.write_text('content')
        self.mirror.sync(source)
        source.rename(self.root / 'new')
        self.mirror.sync(self.root / 'new')
        self.assertEqual(self.mirrored('old').read_text(), 'content')
        self.assertEqual(self.mirrored('new').read_text(), 'content')

    def test_nested_mount_is_excluded_in_both_paths(self):
        nested = self.root / 'mounted'
        nested.mkdir()
        (nested / 'file').write_text('outside filesystem')
        with patch.object(storage, '_mounts', return_value={nested}):
            self.mirror.sync(nested / 'file')
            self.mirror.catch_up()
        self.assertFalse(self.mirrored('mounted').exists())

    def test_catch_up_continues_after_a_saved_path_conflict(self):
        (self.root / 'blocked').mkdir()
        (self.root / 'blocked' / 'file').write_text('first')
        (self.root / 'safe').write_text('second')
        mirror_parent = self.mirrored('blocked').parent
        mirror_parent.mkdir(parents=True)
        for directory in (mirror_parent, *mirror_parent.parents):
            directory.chmod(0o755)
            if directory == self.target / 'live':
                break
        self.mirrored('blocked').symlink_to(self.base, target_is_directory=True)
        with self.assertLogs(level='WARNING') as messages:
            self.mirror.catch_up()
        self.assertEqual(self.mirrored('safe').read_text(), 'second')
        self.assertTrue(any('catch-up skipped 1 entries' in line for line in messages.output))

    def test_failed_sqlite_snapshot_keeps_previous_copy(self):
        source = self.root / 'work.db'
        with sqlite3.connect(source) as db:
            db.execute('CREATE TABLE records (value TEXT)')
            db.execute("INSERT INTO records VALUES ('safe')")
        self.mirror.sync(source)
        source.write_text('invalid database')
        with self.assertRaises(storage.subprocess.CalledProcessError):
            self.mirror.sync(source)
        with sqlite3.connect(self.mirrored('work.db').as_uri() + '?mode=ro&immutable=1', uri=True) as copy:
            self.assertEqual(copy.execute('SELECT value FROM records').fetchall(), [('safe',)])
        self.assertEqual(self.versions('work.db'), [])

    def test_reflink_failure_keeps_live_file(self):
        source = self.root / 'file'
        source.write_text('old')
        self.mirror.sync(source)
        source.write_text('new')
        self.mirror.reflink = True
        with patch.object(storage.subprocess, 'run', side_effect=RuntimeError('failed')):
            with self.assertRaises(RuntimeError):
                self.mirror.sync(source)
        self.assertEqual(self.mirrored('file').read_text(), 'old')

    def test_reflink_with_open_target_descriptor(self):
        source = self.root / 'file'
        source.write_text('old')
        descriptor = os.open(self.target, os.O_RDONLY | os.O_DIRECTORY)
        try:
            mirror = storage.Mirror(Path(f'/proc/self/fd/{descriptor}'), (self.root,))
            mirror.sync(source)
            source.write_text('new')
            try:
                mirror.sync(source)
            except storage.subprocess.CalledProcessError as error:
                self.skipTest(f'test filesystem cannot reflink: {error}')
            self.assertEqual(self.mirrored('file').read_text(), 'new')
            self.assertEqual([p.read_text() for p in self.versions('file')], ['old'])
        finally:
            os.close(descriptor)


if __name__ == '__main__':
    unittest.main()
