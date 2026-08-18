#!/usr/bin/env bats

setup() {
	ROOT="${BATS_TEST_DIRNAME}/../.."
	CONFIG="${ROOT}/.config/tmuxinator/standup.yml"
	PROMPT="${ROOT}/.config/tmuxinator/standup-agent.md"
}

@test "standup starts the live AI reporter" {
	run grep -F 'root: ~/loft' "$CONFIG"
	[ "$status" -eq 0 ]
	run grep -F '__claude_with_monitor.sh --model opus --effort medium --system-prompt-file ~/dev/dotfiles/.config/tmuxinator/standup-agent.md' "$CONFIG"
	[ "$status" -eq 0 ]
	run grep -F -- '--model opus' "$CONFIG"
	[ "$status" -eq 0 ]
	run grep -F -- '--effort medium' "$CONFIG"
	[ "$status" -eq 0 ]
}

@test "report requires Slack, Ursula calendar context, and Linear" {
	run grep -F 'mcp__claude_ai_Slack__slack_search_public_and_private' "$PROMPT"
	[ "$status" -eq 0 ]
	run grep -F 'Do not wait for Ursula' "$PROMPT"
	[ "$status" -eq 0 ]
	run grep -F 'mcp__claude_ai_Google_Calendar__list_events' "$PROMPT"
	[ "$status" -eq 0 ]
	run grep -F 'mcp__linear-server__list_issues' "$PROMPT"
	[ "$status" -eq 0 ]
}

@test "report excludes routine one-to-one meetings but keeps interviews" {
	run grep -F 'Exclude recurring one-to-one meetings completely.' "$PROMPT"
	[ "$status" -eq 0 ]
	run grep -F '`1:1`, `<>`, `<->`, or only two colleague names' "$PROMPT"
	[ "$status" -eq 0 ]
	run grep -F 'Interviews and hiring calls are not one-to-one meetings' "$PROMPT"
	[ "$status" -eq 0 ]
}

@test "report returns every candidate without shared-state tracking or caps" {
	run grep -F 'Do not track or suppress items based on whether a previous standup mentioned them.' "$PROMPT"
	[ "$status" -eq 0 ]
	run grep -F 'every qualifying candidate. Do not impose a bullet or section limit.' "$PROMPT"
	[ "$status" -eq 0 ]
	run grep -F 'Exactly 3 bullets' "$PROMPT"
	[ "$status" -ne 0 ]
	run grep -F 'At most 1 bullet' "$PROMPT"
	[ "$status" -ne 0 ]
	run grep -F 'One link at most per bullet.' "$PROMPT"
	[ "$status" -eq 0 ]
}

@test "report uses project groups and selective markdown links" {
	run grep -F 'Group Yesterday and Today bullets under their project.' "$PROMPT"
	[ "$status" -eq 0 ]
	run grep -F 'Link only the useful reference token' "$PROMPT"
	[ "$status" -eq 0 ]
	run grep -F '[DEVOPS-1352](https://linear.app/loft/issue/DEVOPS-1352): let ai-step trigger a managed agent in ai-agents' "$PROMPT"
	[ "$status" -eq 0 ]
	run grep -F 'force a link onto every item.' "$PROMPT"
	[ "$status" -eq 0 ]
	run grep -F 'Wrap the whole report in one fenced Markdown block.' "$PROMPT"
	[ "$status" -eq 0 ]
	run grep -F 'No checkboxes, date dividers, prior-focus recap' "$PROMPT"
	[ "$status" -eq 0 ]
}

@test "linear issues include one short source-grounded context sentence" {
	run grep -F 'Add exactly one short context sentence after every Linear issue title.' "$PROMPT"
	[ "$status" -eq 0 ]
	run grep -F '4 and 12 words.' "$PROMPT"
	[ "$status" -eq 0 ]
	run grep -F 'Do not restate the title or' "$PROMPT"
	[ "$status" -eq 0 ]
	run grep -F 'invent context.' "$PROMPT"
	[ "$status" -eq 0 ]
	run grep -F 'This connects ai-step directly to managed-agent execution.' "$PROMPT"
	[ "$status" -eq 0 ]
}
