#!/usr/bin/env bats

# The guard exists because a push that rewinds homelab main reverts, live,
# whatever Argo CD had already applied from the dropped commits.
# Every push runs through real git with only this hook installed.

setup() {
	HOOK="${BATS_TEST_DIRNAME}/../../.git-global-hooks/pre-push"
	TMP="$(mktemp -d)"
	HOOKS="${TMP}/hooks"
	mkdir -p "$HOOKS"
	ln -s "$HOOK" "${HOOKS}/pre-push"

	# Keep the personal config (its hooksPath, signing) out of the test repos.
	export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
	export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

	git init -q --bare -b main "${TMP}/origin.git"
	git init -q -b main "${TMP}/work"
	cd "${TMP}/work"
	git config core.hooksPath "$HOOKS"
	git remote add origin "${TMP}/origin.git"
	commit one
	git push -q origin main
	commit two
	git push -q origin main
}

teardown() {
	rm -rf "$TMP"
}

commit() {
	echo "$1" >>file
	git add file
	git commit -q -m "$1"
}

@test "allows a fast-forward push to main" {
	commit three

	run git push origin main

	[ "$status" -eq 0 ]
}

@test "refuses a force push that rewinds main" {
	git reset -q --hard HEAD~1
	commit stale-base

	run git push --force origin main

	[ "$status" -ne 0 ]
	[[ "$output" == *"refusing to rewind main on origin"* ]]
	[ "$(git ls-remote origin refs/heads/main | cut -f1)" != "$(git rev-parse HEAD)" ]
}

@test "refuses a force-with-lease push that rewinds main" {
	git reset -q --hard HEAD~1

	run git push --force-with-lease origin main

	[ "$status" -ne 0 ]
	[[ "$output" == *"refusing to rewind main"* ]]
}

@test "refuses to delete main" {
	run git push origin :main

	[ "$status" -ne 0 ]
	[[ "$output" == *"refusing to delete main on origin"* ]]
}

@test "guards master the same way" {
	git push -q origin main:master
	git reset -q --hard HEAD~1

	run git push --force origin main:master

	[ "$status" -ne 0 ]
	[[ "$output" == *"refusing to rewind master"* ]]
}

@test "allows a force push to any other branch" {
	git push -q origin main:feature
	git reset -q --hard HEAD~1

	run git push --force origin main:feature

	[ "$status" -eq 0 ]
}

@test "allows creating main on an empty remote" {
	git init -q --bare -b main "${TMP}/empty.git"
	git remote add empty "${TMP}/empty.git"

	run git push empty main

	[ "$status" -eq 0 ]
}

@test "lets a deliberate rewrite through with --no-verify" {
	git reset -q --hard HEAD~1

	run git push --force --no-verify origin main

	[ "$status" -eq 0 ]
	[ "$(git ls-remote origin refs/heads/main | cut -f1)" = "$(git rev-parse HEAD)" ]
}
