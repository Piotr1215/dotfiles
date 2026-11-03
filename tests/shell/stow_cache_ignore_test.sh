#!/usr/bin/env bash
set -eo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/packages/dotfiles/.pytest_cache/v/cache" "$fixture/home/.pytest_cache/v/cache"
cp "$repo/.stow-local-ignore" "$fixture/packages/dotfiles/.stow-local-ignore"
printf 'package cache\n' >"$fixture/packages/dotfiles/.pytest_cache/v/cache/nodeids"
printf 'home cache\n' >"$fixture/home/.pytest_cache/v/cache/nodeids"
printf 'config\n' >"$fixture/packages/dotfiles/.sample-config"

output=$(stow -n -v -d "$fixture/packages" -t "$fixture/home" -R dotfiles 2>&1)
[[ "$output" == *'LINK: .sample-config'* ]]
[[ "$output" != *'existing target is'* ]]
[[ $(<"$fixture/home/.pytest_cache/v/cache/nodeids") == 'home cache' ]]
printf 'ok: pytest cache is ignored and real dotfiles remain eligible\n'
