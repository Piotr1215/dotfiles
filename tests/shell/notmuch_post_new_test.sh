#!/usr/bin/env bash
# The notmuch post-new hook hands both email specs to classif and never fails
# notmuch new: no classif, a failing classif, or a full error log all exit 0.
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../../scripts/__notmuch_post_new.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

pass=0
fail=0
check() { # $1=name $2=expected $3=actual
  if [[ "$2" == "$3" ]]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1: want [$2] got [$3]"; fi
}

# $1=exit code of the fake classif (empty: no classif at all)
run_hook() {
  local home="$work/home-$RANDOM"
  mkdir -p "$home/.local/bin"
  if [[ -n "$1" ]]; then
    printf '#!/bin/sh\necho "$@" > "%s/args"\necho "classif broke" >&2\nexit %s\n' "$home" "$1" > "$home/.local/bin/classif"
    chmod +x "$home/.local/bin/classif"
  fi
  HOME="$home" XDG_STATE_HOME="$home/state" PATH="/usr/bin:/bin" bash "$HOOK"
  echo "$?:$home"
}

out="$(run_hook "")"
check "no classif exits 0" 0 "${out%%:*}"

out="$(run_hook 0)"
home="${out#*:}"
check "passes both specs with their tags" "notmuch email-bulk=bulk email-action=action" "$(cat "$home/args")"

out="$(run_hook 1)"
home="${out#*:}"
check "a failing classif exits 0" 0 "${out%%:*}"
check "classif's stderr lands in the error log" "classif broke" "$(cat "$home/state/classif/notmuch.err")"

home="$work/full"
mkdir -p "$home/.local/bin" "$home/state/classif"
head -c 1048577 /dev/zero | tr '\0' x > "$home/state/classif/notmuch.err"
printf '#!/bin/sh\necho again >&2\nexit 1\n' > "$home/.local/bin/classif"
chmod +x "$home/.local/bin/classif"
HOME="$home" XDG_STATE_HOME="$home/state" PATH="/usr/bin:/bin" bash "$HOOK"
check "a full error log starts over" "again" "$(cat "$home/state/classif/notmuch.err")"

echo "$pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
