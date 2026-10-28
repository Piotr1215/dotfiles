#!/usr/bin/env bats

setup() {
	HOOK="${BATS_TEST_DIRNAME}/../../.git-work-hooks/pre-push"
	TMP="$(mktemp -d)"
	mkdir -p "${TMP}/hooks"
	ln -s "$HOOK" "${TMP}/hooks/pre-push"
	export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
	export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
	git init -q --bare -b main "${TMP}/origin.git"
	git init -q -b main "${TMP}/work"
	cd "${TMP}/work"
	git config core.hooksPath "${TMP}/hooks"
	git remote add origin "${TMP}/origin.git"
	commit one
}

teardown() {
	rm -rf "$TMP"
}

commit() {
	echo "$1" >>file
	git add file
	git commit -q -m "$1"
}

@test "allows an update to an existing numeric-slug branch" {
	git checkout -q -b devops-1683/20261020-164338
	git push -q --no-verify origin HEAD
	commit two

	run git push origin HEAD

	[ "$status" -eq 0 ]
	[ "$(git ls-remote origin refs/heads/devops-1683/20261020-164338 | cut -f1)" = "$(git rev-parse HEAD)" ]
}

@test "refuses a new numeric-slug branch" {
	git checkout -q -b devops-1683/20261020-164338

	run git push origin HEAD

	[ "$status" -ne 0 ]
	[[ "$output" == *"Branch has auto-generated slug"* ]]
	[ -z "$(git ls-remote origin refs/heads/devops-1683/20261020-164338)" ]
}

@test "refuses a push containing a new ref even when another ref exists" {
	git checkout -q -b devops-1683/20261020-164338
	git push -q --no-verify origin HEAD
	commit two

	run git push origin HEAD:refs/heads/devops-1683/20261020-164338 HEAD:refs/heads/new-branch

	[ "$status" -ne 0 ]
	[[ "$output" == *"Branch has auto-generated slug"* ]]
}

@test "still refuses pushes from a protected branch" {
	git push -q --no-verify origin main
	commit two

	run git push origin main

	[ "$status" -ne 0 ]
	[[ "$output" == *"Blocking push to protected branch: main"* ]]
}
