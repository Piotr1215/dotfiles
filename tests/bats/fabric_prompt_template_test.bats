#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	TEMPLATE_TOOL="$REPO_ROOT/scripts/__fabric_prompt_template.sh"
}

@test "variables finds lowercase and uppercase placeholders once in encounter order" {
	run bash "$TEMPLATE_TOOL" variables <<'EOF'
{{input}} for {{AUDIENCE}}, then repeat {{input}} and use {{topic_2}}.
EOF
	[ "$status" -eq 0 ]
	[ "$output" = $'input\nAUDIENCE\ntopic_2' ]
}

@test "prepare adds an editable variable form before the unchanged prompt" {
	run bash "$TEMPLATE_TOOL" prepare <<'EOF'
Explain {{topic}} to {{audience}}.
EOF
	[ "$status" -eq 0 ]
	[[ "$output" == *$'topic=\naudience='* ]]
	[[ "$output" == *$'--- FABRIC PROMPT ---\n\nExplain {{topic}} to {{audience}}.'* ]]
}

@test "prepare treats input specially and appends it when the pattern omits it" {
	run bash "$TEMPLATE_TOOL" prepare <<'EOF'
Explain {{topic}} clearly.
EOF
	[ "$status" -eq 0 ]
	[[ "$output" == $'input=\ntopic='* ]]
	[[ "$output" == *$'Explain {{topic}} clearly.\n{{input}}' ]]
}

@test "prepare removes a duplicate legacy user_request line when input already exists" {
	run bash "$TEMPLATE_TOOL" prepare <<'EOF'
Echo the request.
$user_request
Request: {{input}}
EOF
	[ "$status" -eq 0 ]
	[[ "$output" != *'$user_request'* ]]
	[ "$(printf '%s' "$output" | grep -o '{{input}}' | wc -l)" -eq 1 ]
}

@test "render substitutes repeated placeholders and preserves shell characters literally" {
	run bash "$TEMPLATE_TOOL" render <<'EOF'
# Fill variables below.
input=$HOME `date` & one=two

--- FABRIC PROMPT ---

First: {{input}}
Again: {{input}}
EOF
	[ "$status" -eq 0 ]
	[ "$output" = $'First: $HOME `date` & one=two\nAgain: $HOME `date` & one=two' ]
}

@test "render leaves blank variables as visible placeholders" {
	run bash "$TEMPLATE_TOOL" render <<'EOF'
input=

--- FABRIC PROMPT ---

Request: {{input}}
EOF
	[ "$status" -eq 0 ]
	[ "$output" = 'Request: {{input}}' ]
}
