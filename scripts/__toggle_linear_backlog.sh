#!/usr/bin/env bash
# __toggle_linear_backlog.sh - taskwarrior-tui key 7: move each selected task's
# Linear issue (linear_issue_id) in or out of the team's Backlog state.
# A +backlog task, or any task in the backlog report, goes to Todo and loses
# +backlog. Any other task goes to Backlog, gains +backlog and loses +fresh.
# The task's tags change only after Linear confirms the new state.
# GraphQL variables ($id, $state) are literal text, not shell expansions.
# shellcheck disable=SC2016
set -eo pipefail

linear_url=${LINEAR_GRAPHQL_URL:-https://api.linear.app/graphql}
api_key=""
messages=()
failed=0

# Prints the Linear API key: $LINEAR_API_KEY, else the work pass entry.
linear_key() {
	if [[ -n "${LINEAR_API_KEY:-}" ]]; then
		printf '%s' "$LINEAR_API_KEY"
	else
		pass show work/LINEAR_API_KEY 2>/dev/null | head -n 1 || true
	fi
}

# Posts one GraphQL request (query, variables JSON) and prints the response.
# The key travels in a header file, never on the command line.
linear_post() {
	local body
	body=$(jq -n --arg q "$1" --argjson v "$2" '{query: $q, variables: $v}')
	curl -fsS -X POST \
		-H "Content-Type: application/json" \
		-H @<(printf 'Authorization: %s\n' "$api_key") \
		--data "$body" "$linear_url"
}

# Records one line of feedback; a second argument of "fail" marks a failure.
report() {
	messages+=("$1")
	if [[ "${2:-}" == fail ]]; then
		failed=1
		echo "$1" >&2
	else
		echo "$1"
	fi
}

# Moves one task's issue and syncs its tags.
toggle_task() {
	local uuid=$1 issue tags target id response current_id current_name state_id confirmed
	local -a filter changes
	issue=$(task _get "${uuid}.linear_issue_id")
	if [[ -z "$issue" ]]; then
		report "Skipped $(task _get "${uuid}.description" | cut -c1-40): no linear_issue_id"
		return 0
	fi
	tags=",$(task _get "${uuid}.tags"),"
	if [[ "$tags" == *,backlog,* || "${TASKWARRIOR_TUI_REPORT:-}" == backlog ]]; then
		target=Todo
	else
		target=Backlog
	fi

	if [[ -z "$api_key" ]]; then
		api_key=$(linear_key)
		[[ -n "$api_key" ]] || { report "$issue: no Linear API key (LINEAR_API_KEY or pass work/LINEAR_API_KEY)" fail; return 0; }
	fi

	if ! response=$(linear_post 'query IssueStates($id: String!) { issue(id: $id) { id state { id name } team { states(first: 250) { nodes { id name } pageInfo { hasNextPage } } } } }' \
		"$(jq -n --arg id "$issue" '{id: $id}')"); then
		report "$issue: Linear lookup failed" fail
		return 0
	fi
	# State names match case-insensitively and ignore spaces, so "To Do" counts as Todo.
	if ! IFS=$'\t' read -r current_id current_name state_id < <(jq -er --arg want "$target" '
		def norm: ascii_downcase | gsub(" "; "");
		if (.errors // [] | length) != 0 or (.data.issue.id | type) != "string" or
		   .data.issue.team.states.pageInfo.hasNextPage != false then error("invalid lookup")
		else [.data.issue.team.states.nodes[] | select((.name | norm) == ($want | norm)) | .id] as $ids |
		  if ($ids | length) != 1 then error("missing or ambiguous state")
		  else [.data.issue.state.id, .data.issue.state.name, $ids[0]] | @tsv end
		end' <<<"$response" 2>/dev/null); then
		report "$issue: no unique $target state in its team" fail
		return 0
	fi

	if [[ "$current_id" != "$state_id" ]]; then
		if ! response=$(linear_post 'mutation MoveIssue($id: String!, $state: String!) { issueUpdate(id: $id, input: { stateId: $state }) { success } }' \
			"$(jq -n --arg id "$issue" --arg s "$state_id" '{id: $id, state: $s}')") ||
			! jq -e '.data.issueUpdate.success == true' <<<"$response" >/dev/null; then
			report "$issue: Linear update failed" fail
			return 0
		fi
		if ! response=$(linear_post 'query IssueState($id: String!) { issue(id: $id) { state { id name } } }' \
			"$(jq -n --arg id "$issue" '{id: $id}')") ||
			! confirmed=$(jq -er '.data.issue.state.id' <<<"$response") || [[ "$confirmed" != "$state_id" ]]; then
			report "$issue: Linear did not confirm $target" fail
			return 0
		fi
	fi

	if [[ "$target" == Backlog ]]; then
		[[ "$tags" == *,backlog,* ]] || changes+=(+backlog)
		[[ "$tags" != *,fresh,* ]] || changes+=(-fresh)
	else
		[[ "$tags" != *,backlog,* ]] || changes+=(-backlog)
	fi
	if ((${#changes[@]})); then
		# A bare UUID filter loads every task; `<id> uuid:<uuid>` reads pending ones only.
		id=$(task _get "${uuid}.id")
		filter=("$uuid")
		[[ -z "$id" || "$id" == 0 ]] || filter=("$id" "uuid:$uuid")
		if ! task rc.bulk=0 rc.confirmation=off rc.verbose=nothing rc.context=none "${filter[@]}" modify "${changes[@]}" >/dev/null; then
			report "$issue: moved $current_name -> $target, but the task tags did not change" fail
			return 0
		fi
	fi
	report "$issue: $current_name -> $target"
}

[[ $# -gt 0 ]] || { echo 'Select a task first' >&2; exit 1; }
for uuid in "$@"; do
	toggle_task "$uuid"
done

if command -v notify-send >/dev/null; then
	urgency=normal
	((failed == 0)) || urgency=critical
	notify-send -u "$urgency" "Linear backlog" "$(printf '%s\n' "${messages[@]}")" 2>/dev/null || true
fi
exit "$failed"
