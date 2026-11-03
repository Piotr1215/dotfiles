#!/usr/bin/env bats
#
# Covers scripts/__gh_admin.sh. The secret library and gh are stubbed, so no
# YubiKey tap, bastion read or GitHub call happens.

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	SCRIPT="$REPO_ROOT/scripts/__gh_admin.sh"
	STUB="$BATS_TEST_TMPDIR"
	cat >"$STUB/lib" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == read ]] || exit 9
[[ -f "$STUB_FAIL" ]] && exit 1
printf '%s' "${STUB_TOKEN-admin-token-value}"
EOF
	cat >"$STUB/gh" <<'EOF'
#!/usr/bin/env bash
printf 'gh token=%s args=%s\n' "${GH_TOKEN:-}" "$*"
EOF
	cat >"$STUB/cmd" <<'EOF'
#!/usr/bin/env bash
printf 'cmd token=%s args=%s\n' "${GH_TOKEN:-}" "$*"
EOF
	chmod +x "$STUB/lib" "$STUB/gh" "$STUB/cmd"
	export SECRET_LIB="$STUB/lib" GH_BIN="$STUB/gh" STUB_FAIL="$STUB/fail"
	unset GH_TOKEN STUB_TOKEN
}

@test "passes gh arguments through with the admin token" {
	run "$SCRIPT" api orgs/loft-sh/invitations
	[ "$status" -eq 0 ]
	[ "$output" = "gh token=admin-token-value args=api orgs/loft-sh/invitations" ]
}

@test "-- runs the given command with the admin token instead of gh" {
	run "$SCRIPT" -- "$STUB/cmd" --flag value
	[ "$status" -eq 0 ]
	[ "$output" = "cmd token=admin-token-value args=--flag value" ]
}

@test "a failed bastion read exits 1 and never runs gh" {
	touch "$STUB/fail"
	run "$SCRIPT" api user
	[ "$status" -eq 1 ]
	[[ "$output" == *"could not read GH_ADMIN_TOKEN"* ]]
	[[ "$output" != *"gh token="* ]]
}

@test "an empty token exits 1 and never runs gh" {
	export STUB_TOKEN=""
	run "$SCRIPT" api user
	[ "$status" -eq 1 ]
	[[ "$output" != *"gh token="* ]]
}

@test "no arguments, or a bare --, prints usage and exits 2" {
	run "$SCRIPT"
	[ "$status" -eq 2 ]
	[[ "$output" == *usage:* ]]
	run "$SCRIPT" --
	[ "$status" -eq 2 ]
}

@test "the token stays out of the caller's environment" {
	run bash -c '"$1" api user >/dev/null; printf "after=%s" "${GH_TOKEN:-}"' _ "$SCRIPT"
	[ "$output" = "after=" ]
}
