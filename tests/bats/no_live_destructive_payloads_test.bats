#!/usr/bin/env bats

# Scan text as data; never evaluate any of the commands being checked.
scan_payloads() {
  python3 - "$@" <<'PY'
import pathlib
import re
import sys

# Keep fragments separate so this scanner does not match its own source.
rm = r'r' + r'm'
find = r'fi' + r'nd'
home = r'(?:~(?:/[^\s;"\']*)?|\$(?:HOME|\{HOME\})(?:/[^\s;"\']*)?|/(?:\*[^\s;"\']*)?)'
command = r'(?<![\w/.-])(?:[\w./-]*/)?'
force = r'(?:--force\b|-[A-Za-z]*f[A-Za-z]*\b)'
recursive = r'(?:--recursive\b|-[A-Za-z]*[rR][A-Za-z]*\b)'
no_root = r'--no-preserve-' + r'root\b'
rm_command = re.compile(command + rm + r'\b([^\n;|&]*)')
find_command = re.compile(command + find + r'\b([^\n;|&]*)')
home_target = re.compile(r'(?<![\w./$])' + home + r'(?=$|[\s;"\'])')
no_root_option = re.compile(no_root)
force_option = re.compile(force)
recursive_option = re.compile(recursive)
delete_action = re.compile(r'-(?:de' + r'lete\b|exec(?:dir)?\s+(?:\S*/)?' + rm + r'\b)')

# Map a test path to a one-line reason only after inspecting each inert hit.
ALLOWLIST = {}

failed = False
for root in map(pathlib.Path, sys.argv[1:]):
    files = [root] if root.is_file() else sorted(p for p in root.rglob('*') if p.is_file())
    for path in files:
        if str(path) in ALLOWLIST:
            continue
        try:
            text = path.read_bytes().decode('utf-8', errors='replace')
        except OSError as exc:
            print(f'{path}: cannot scan: {exc}', file=sys.stderr)
            failed = True
            continue
        logical_lines = []
        pending = ''
        start = 1
        for number, part in enumerate(text.splitlines(), 1):
            if not pending:
                start = number
            if part.rstrip().endswith('\\'):
                pending += part.rstrip()[:-1] + ' '
            else:
                logical_lines.append((start, pending + part))
                pending = ''
        if pending:
            logical_lines.append((start, pending))
        for number, line in logical_lines:
            bad = bool(no_root_option.search(line))
            for match in rm_command.finditer(line):
                args = match.group(1)
                if no_root_option.search(args) or (force_option.search(args) and recursive_option.search(args) and home_target.search(args)):
                    bad = True
            for match in find_command.finditer(line):
                args = match.group(1)
                if home_target.search(args) and delete_action.search(args):
                    bad = True
            if bad:
                print(f'{path}:{number}: destructive payload')
                failed = True
sys.exit(1 if failed else 0)
PY
}

@test "test files contain no live destructive payloads" {
  run scan_payloads "$BATS_TEST_DIRNAME/.."
  [ "$status" -eq 0 ] || { printf '%s\n' "$output" >&2; false; }
}

@test "scanner rejects destructive payloads as text" {
  local fixture="$BATS_TEST_TMPDIR/dangerous"
  printf '%s\n' \
    'r''m -rf /' \
    'r''m -rf /*' \
    'r''m -rfv ~/*' \
    'r''m -r -f ~/' \
    'r''m -fr "$HOME"' \
    'r''m -r -f -- "${HOME}/docs"' \
    'r''m --force --recursive "$HOME/"' \
    'r''m -Rf ~' \
    '/bin/r''m -rf /' \
    'r''m --recursive --force ~/docs' \
    'r''m --no-preserve-'"root /tmp/example" \
    'fi''nd ~ -delete' \
    'fi''nd "$HOME" -exec rm {} +' \
    'fi''nd / -execdir /bin/rm {} +' > "$fixture"
  run scan_payloads "$fixture"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$output" | wc -l)" -eq 14 ]
}

@test "scanner rejects a destructive command continued on the next line" {
  local fixture="$BATS_TEST_TMPDIR/continued"
  printf '%s\n' 'r''m -rf \' '  "$HOME"' > "$fixture"
  run scan_payloads "$fixture"
  [ "$status" -eq 1 ]
}

@test "scanner permits temporary paths and non-destructive commands" {
  local fixture="$BATS_TEST_TMPDIR/safe"
  printf '%s\n' \
    'r''m -rf /tmp/example' \
    'r''m -rf "$BATS_TEST_TMPDIR/example"' \
    'r''m -rf "$T/example"' \
    'r''m -rf "$TMPDIR/example"' \
    'r''m -rf "$mktemp_dir/example"' \
    'r''m -rf /homework/example' \
    'r''m -r "$HOME"' \
    'fi''nd /tmp/example -delete' \
    'fi''nd "$HOME" -print' > "$fixture"
  run scan_payloads "$fixture"
  [ "$status" -eq 0 ]
}
