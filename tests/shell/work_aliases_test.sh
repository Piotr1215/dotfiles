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

if [[ $(head -n 1 "$repo_root/.zsh_aliases.work") == '# git-crypt work aliases' ]]; then
  definition=$(rg '^alias aws-loft-management-login=' "$repo_root/.zsh_aliases.work")
  printf '# git-crypt work aliases\n%s\n' "$definition" > "$fixture_repo/.zsh_aliases.work"
  mkdir -p "$scratch/bin"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*"\n' > "$scratch/bin/aws"
  chmod +x "$scratch/bin/aws"
  actual=$(PATH="$scratch/bin:$PATH" zsh -f -c 'source "$1"; eval aws-loft-management-login' \
    test "$scratch/home/.zsh_aliases")
  expected='login --profile loft-management-iam --region eu-central-1 --remote'
  [[ "$actual" == "$expected" ]] || { echo 'FAIL: AWS login alias arguments changed' >&2; exit 1; }
  echo 'PASS: AWS login alias uses the work profile, region and remote authentication'
fi
