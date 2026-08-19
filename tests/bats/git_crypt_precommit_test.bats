#!/usr/bin/env bats

# The guard exists because filter.git-crypt.clean was silently set to `cat`,
# which turned every "encrypted" file into a plaintext commit on a public repo.

setup() {
	HOOK="${BATS_TEST_DIRNAME}/../../.git-global-hooks/pre-commit"
	REPO="$(mktemp -d)"
	BIN="${REPO}/bin"
	mkdir -p "$BIN"

	# The hook's first block shells out to stow against the live dotfiles tree.
	# Stub it so this test measures the git-crypt guard and nothing else.
	printf '#!/bin/sh\nexit 0\n' >"${BIN}/stow"
	chmod +x "${BIN}/stow"

	git init -q "$REPO"
	echo 'secret.conf filter=git-crypt diff=git-crypt' >"${REPO}/.gitattributes"
	export HOOK REPO BIN
}

teardown() {
	rm -rf "$REPO"
}

# $1: what the fake git-crypt prints for `status`
fake_git_crypt() {
	printf '#!/bin/sh\ncat <<EOF\n%s\nEOF\n' "$1" >"${BIN}/git-crypt"
	chmod +x "${BIN}/git-crypt"
}

@test "blocks the commit when a git-crypt file is stored in plaintext" {
	fake_git_crypt "    encrypted: secret.conf *** WARNING: staged/committed version is NOT ENCRYPTED! ***"

	cd "$REPO"
	run env PATH="${BIN}:${PATH}" bash "$HOOK"

	[ "$status" -eq 1 ]
	[[ "$output" == *"secret.conf"* ]]
}

@test "names the broken filter config as the cause" {
	fake_git_crypt "    encrypted: secret.conf *** WARNING: staged/committed version is NOT ENCRYPTED! ***"
	git -C "$REPO" config filter.git-crypt.clean cat

	cd "$REPO"
	run env PATH="${BIN}:${PATH}" bash "$HOOK"

	[[ "$output" == *"filter.git-crypt.clean is 'cat'"* ]]
	[[ "$output" == *"git config filter.git-crypt.clean"* ]]
	[[ "$output" == *"git-crypt status -f"* ]]
}

@test "allows the commit when every marked file is encrypted" {
	fake_git_crypt "    encrypted: secret.conf"

	cd "$REPO"
	run env PATH="${BIN}:${PATH}" bash "$HOOK"

	[ "$status" -eq 0 ]
}

@test "stays out of the way in repos that do not use git-crypt" {
	fake_git_crypt "    encrypted: secret.conf *** WARNING: staged/committed version is NOT ENCRYPTED! ***"
	rm "${REPO}/.gitattributes"

	cd "$REPO"
	run env PATH="${BIN}:${PATH}" bash "$HOOK"

	[ "$status" -eq 0 ]
}
