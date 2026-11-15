#!/usr/bin/env bash
# Skips the calling test when a file it reads is still git-crypt ciphertext.
# CI checks out encrypted files without the key, so tests that read .taskrc or
# scripts/__backup.sh can only run on a machine that unlocked the repo.
skip_if_encrypted() {
	local file="$1" magic
	magic="$(head -c 9 "$file" 2>/dev/null | tr -d '\0')"
	[[ "$magic" == GITCRYPT ]] && skip "${file##*/} is git-crypt ciphertext here"
	return 0
}
