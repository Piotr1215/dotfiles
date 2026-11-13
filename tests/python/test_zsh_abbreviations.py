"""Exercise abbreviation widgets in a real interactive ZLE session."""
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

import pexpect

SOURCE = Path(__file__).resolve().parents[2] / '.zsh_abbreviations'


class AbbreviationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        for name, content in {
            'fzf': '#!/bin/sh\n[ "$PICK" != cancel ] || exit 1\nsed -n "${PICK:-1}p"\n',
            'fd': '#!/bin/sh\nprintf "%s\\n" /tmp/selected\n',
        }.items():
            path = self.root / name
            path.write_text(content)
            path.chmod(0o755)

    def tearDown(self):
        self.temp.cleanup()

    def expand(self, line, *, pick='1', cwd=None, left=0):
        result = self.root / 'result'
        result.unlink(missing_ok=True)
        env = dict(os.environ, PATH=f'{self.root}:{os.environ["PATH"]}', PICK=pick,
                   RESULT=str(result), TERM='xterm')
        child = pexpect.spawn('zsh', ['-f'], cwd=str(cwd or self.root), env=env,
                              encoding='utf-8', timeout=5, echo=False)
        try:
            child.sendline("setopt extendedglob; source " + str(SOURCE) +
                           "; capture() { print -rn -- $BUFFER > $RESULT; print -rn -- $'\\0'$CURSOR >> $RESULT; }; zle -N capture; bindkey '^O' capture; PS1='READY> '")
            child.expect_exact('READY> ')
            child.send(line)
            if left:
                child.send('\x1b[D' * left)
            child.send(' \x0f')
            deadline = time.monotonic() + 5
            while not result.exists() and time.monotonic() < deadline:
                time.sleep(.01)
            data = result.read_bytes()
            buffer, cursor = data.rsplit(b'\0', 1)
            return buffer.decode(), int(cursor)
        finally:
            child.close(force=True)

    def test_jq_and_cursor(self):
        for line, expected in [('curl https://example _jq', "curl -s https://example | jq -r '.'"),
                               ('curl -sS url _jq', "curl -sS url | jq -r '.'"),
                               (' curl url _jq', " curl url | jq -r '.'"),
                               ("echo 'a b' | cat _jq", "echo 'a b' | cat | jq -r '.'")]:
            with self.subTest(line=line):
                buf, pos = self.expand(line)
                self.assertEqual(buf, expected)
                self.assertEqual(buf[pos:], ".'")

    def test_duplicate_and_failure(self):
        for line, expected in [("mv 'a b' _dup", "mv 'a b' 'a b'"), ('_dup', '_dup'), ('mv _dup', 'mv _dup'), ('echo > _dup', 'echo > _dup')]:
            with self.subTest(line=line):
                buf, pos = self.expand(line)
                self.assertEqual((buf, pos), (expected, len(expected)))

    def test_substitution_preserves_right_buffer(self):
        buf, pos = self.expand('fd -e md _subTAIL', left=4)
        self.assertEqual((buf, pos), (' $(fd -e md)TAIL', 0))
        self.assertEqual(self.expand('_sub'), ('_sub', 4))

    def test_expansion_does_not_execute_substitutions(self):
        marker = self.root / 'executed'
        line = f'echo $(touch {marker}) _sub'
        self.assertEqual(self.expand(line)[0], f' $(echo $(touch {marker}))')
        self.assertFalse(marker.exists())

    def test_for_selection_cancel_and_complex(self):
        buf, pos = self.expand("kubectl delete ns -l 'a b' c _for", pick='4')
        self.assertEqual(buf, 'for x in \'a b\' c; do kubectl delete ns -l "$x"; done')
        self.assertEqual(pos, len(buf))
        self.assertEqual(self.expand('echo a _for')[0], 'for x in a; do echo "$x"; done')
        self.assertEqual(self.expand("echo 'a&b' _for")[0], 'for x in \'a&b\'; do echo "$x"; done')
        for line, pick in [('echo a b _for', 'cancel'), ('echo a | cat _for', '1'), ('echo a 2>out _for', '1'), ('_for', '1')]:
            self.assertEqual(self.expand(line, pick=pick), (line, len(line)))

    def test_branch_and_failures(self):
        self.assertEqual(self.expand('_br'), ('_br', 3))
        subprocess.run(['git', 'init', '-q', str(self.root / 'repo')], check=True)
        repo = self.root / 'repo'
        subprocess.run(['git', '-C', str(repo), 'symbolic-ref', 'HEAD', 'refs/heads/test-branch'], check=True)
        self.assertEqual(self.expand('git switch _br', cwd=repo)[0], 'git switch test-branch ')
        subprocess.run(['git', '-C', str(repo), 'symbolic-ref', 'HEAD', 'refs/heads/test$branch'], check=True)
        self.assertEqual(self.expand('_br', cwd=repo)[0], r'test\$branch ')
        subprocess.run(['git', '-C', str(repo), '-c', 'user.name=test', '-c', 'user.email=test@example.com',
                        'commit', '--allow-empty', '-qm', 'test'], check=True)
        subprocess.run(['git', '-C', str(repo), 'checkout', '-q', '--detach'], check=True)
        self.assertEqual(self.expand('_br', cwd=repo), ('_br', 3))

    def test_filt_cursor(self):
        buf, pos = self.expand('echo ?filt')
        self.assertEqual(buf, r'!!:gs//\/tmp\/selected/')
        self.assertEqual(pos, len('!!:gs/'))


if __name__ == '__main__':
    unittest.main()
