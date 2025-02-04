#!/usr/bin/env bash
set -eo pipefail
source /home/decoder/dev/dotfiles/scripts/__lib_taskwarrior_interop.sh

get_task_id_by_description() {
	local description="$1"
	task status:pending export |
		jq -r --arg desc "$description" '.[] | select(.description == $desc) | .uuid'
}

get_review_prs() {
	gh search prs --involves Piotr1215 --owner loft-sh --state open --limit 100 --json title,url,number,repository --jq '.'
}

notify() {
	local task_desc="$1"

	dunstify \
		--timeout 10000 \
		--action="default,View in Taskwarrior" \
		--icon=appointment-soon \
		"New PRs assigned for review" \
		"${task_desc}" 2>/dev/null | {
		read -r response
		if [ "$response" = "default" ]; then
			tmux switch-client -t task
		fi
	} &
}

main() {
	local pr_title pr_url repo_name task_uuid
	local prs_added=0

	while read -r pr; do
		pr_title=$(echo "$pr" | jq -r '.title')
		pr_url=$(echo "$pr" | jq -r '.url')
		repo_name=$(echo "$pr" | jq -r '.repository.name')
		task_uuid=$(get_task_id_by_description "$pr_title")

		if [[ -z "$task_uuid" ]]; then
			echo "Creating new task for PR: $pr_title"
			task_uuid=$(create_task "$pr_title" "+pr" "+kill" "project:pr-reviews" "repo:$repo_name") || true
			annotate_task "$task_uuid" "$pr_url" || true
			notify "$pr_title" 0
			prs_added=$((prs_added + 1))
		else
			echo "Task already exists for PR: $pr_title"
		fi
	done < <(get_review_prs | jq -c '.[]')
}

main
