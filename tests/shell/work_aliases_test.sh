#!/usr/bin/env bash
set -eo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
fixture_repo="$scratch/repo with spaces"
mkdir -p "$fixture_repo" "$scratch/home"
cp "$repo_root/.zsh_aliases" "$fixture_repo/.zsh_aliases"
ln -s "$fixture_repo/.zsh_aliases" "$scratch/home/.zsh_aliases"

# Source the real alias file through its usual home-directory symlink.
has_work_alias() {
  zsh -f -c 'source "$1"; alias aws-loft-management-login >/dev/null 2>&1' \
    test "$scratch/home/.zsh_aliases"
}

if has_work_alias; then
  echo 'FAIL: missing work file loaded an alias' >&2
  exit 1
fi

printf '\0GITCRYPT\0locked' > "$fixture_repo/.zsh_aliases.work"
if has_work_alias; then
  echo 'FAIL: encrypted work file loaded an alias' >&2
  exit 1
fi

printf '# unexpected header\nalias aws-loft-management-login=true\n' > "$fixture_repo/.zsh_aliases.work"
if has_work_alias; then
  echo 'FAIL: invalid work file loaded an alias' >&2
  exit 1
fi

printf '# git-crypt work aliases\nalias aws-loft-management-login=true\n' > "$fixture_repo/.zsh_aliases.work"
has_work_alias
echo 'PASS: missing, encrypted and invalid files stay gated; decrypted aliases load'
