#!/usr/bin/env bats
# jev asks TypeSafe's Jev one typed question from the shell. Piotr typed
# `jev "hi there"` on 2026-10-06 and the bare curl function sat waiting on
# stdin, because Jev takes a JSON body, not an argument. These tests stub curl:
# they check the body jev builds, how it prints each answer type, and that the
# key never reaches argv.

SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__jev.sh"

setup() {
	TMP=$(mktemp -d)
	mkdir -p "$TMP/bin"
	# Fake curl: record argv, the header file it was handed and the body on
	# stdin, then print the canned response.
	cat >"$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$STUB_DIR/argv"
prev=""
for a in "$@"; do
	if [[ "$prev" == "-H" && "$a" == @* ]]; then cat "${a#@}" >>"$STUB_DIR/headers"; fi
	prev="$a"
done
cat >"$STUB_DIR/body"
printf '%s' "$STUB_RESPONSE"
EOF
	chmod +x "$TMP/bin/curl"
	export PATH="$TMP/bin:$PATH" STUB_DIR="$TMP" TYPESAFE_API_KEY="sk-test-secret"
}

teardown() {
	rm -rf "$TMP"
}

@test "a plain question sends a noul and prints the probability" {
	export STUB_RESPONSE='{"answers":{"q":{"noul":0.8312}}}'
	run "$SCRIPT" "did it run out of memory?" "exit code 137"
	[ "$status" -eq 0 ]
	[ "$output" = "0.83" ]
	[ "$(jq -r '.questions.q.type' "$TMP/body")" = "noul" ]
	[ "$(jq -r '.state.input' "$TMP/body")" = "exit code 137" ]
	[[ "$(jq -r '.questions.q.instructions' "$TMP/body")" == *"did it run out of memory?"* ]]
}

@test "input piped on stdin becomes the state" {
	export STUB_RESPONSE='{"answers":{"q":{"noul":0.1}}}'
	run bash -c "printf 'line one\nline two' | '$SCRIPT' 'is this an error?'"
	[ "$status" -eq 0 ]
	[ "$(jq -r '.state.input' "$TMP/body")" = $'line one\nline two' ]
}

@test "-c sends a choice with the options as criteria and prints pick and confidence" {
	export STUB_RESPONSE='{"answers":{"q":{"choice":"fix","confidence":0.912}}}'
	run "$SCRIPT" -c "feature, fix,docs" "what kind of change?" "repair the login loop"
	[ "$status" -eq 0 ]
	[ "$output" = "fix 0.91" ]
	[ "$(jq -c '.questions.q.criteria' "$TMP/body")" = '{"feature":null,"fix":null,"docs":null}' ]
}

@test "-s sends ordered levels and names the nearest one" {
	export STUB_RESPONSE='{"answers":{"q":{"score":1.62}}}'
	run "$SCRIPT" -s "can wait,this week,today" "how urgent?" "prod is down"
	[ "$status" -eq 0 ]
	[ "$output" = "1.62 today" ]
	[ "$(jq -c '.questions.q.criteria' "$TMP/body")" = '["can wait","this week","today"]' ]
}

@test "-j prints the raw response" {
	export STUB_RESPONSE='{"answers":{"q":{"noul":0.5}},"usage":{"tokens":9}}'
	run "$SCRIPT" -j "q?" "x"
	[ "$status" -eq 0 ]
	[ "$(jq -r '.usage.tokens' <<<"$output")" = "9" ]
}

@test "the key goes in a header file, never in curl's argv" {
	export STUB_RESPONSE='{"answers":{"q":{"noul":0.5}}}'
	run "$SCRIPT" "q?" "x"
	[ "$status" -eq 0 ]
	! grep -q "sk-test-secret" "$TMP/argv"
	grep -q "Authorization: Bearer sk-test-secret" "$TMP/headers"
}

@test "no input on a terminal or argument is refused before any request" {
	export STUB_RESPONSE='{}'
	run "$SCRIPT" "hi there" </dev/null
	[ "$status" -eq 1 ]
	[[ "$output" == *"nothing to judge"* ]]
	[ ! -f "$TMP/body" ]
}

@test "a choice with one option is refused" {
	export STUB_RESPONSE='{}'
	run "$SCRIPT" -c "only" "q?" "x"
	[ "$status" -eq 1 ]
	[[ "$output" == *"at least two options"* ]]
}

@test "an API error is reported, not printed as an answer" {
	export STUB_RESPONSE='{"detail":"invalid api key"}'
	run "$SCRIPT" "q?" "x"
	[ "$status" -eq 1 ]
	[[ "$output" == *"invalid api key"* ]]
}

@test "no question prints usage and fails" {
	run "$SCRIPT"
	[ "$status" -eq 1 ]
	[[ "$output" == *"Usage: jev QUESTION"* ]]
}
