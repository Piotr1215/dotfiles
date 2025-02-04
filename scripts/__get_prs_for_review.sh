#!/usr/bin/env bash
set -eo pipefail
source /home/decoder/dev/dotfiles/scripts/__lib_taskwarrior_interop.sh

get_task_id_by_description() {
	local description="$1"
	task status:pending project:pr-reviews export |
		jq -r --arg desc "$description" '.[] | select(.description == ($desc | rtrimstr(" ") | ltrimstr(" "))) | .uuid'
}

get_all_pending_pr_tasks() {
	task status:pending project:pr-reviews export |
		jq -r '.[] | .description'
}

get_review_prs() {
	gh search prs --involves Piotr1215 --owner loft-sh --state open --limit 100 --json title,url,number,repository,createdAt --jq '.'
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
	local pr_title pr_url repo_name task_uuid created_at updated_at entry_ts
	local prs_added=0
	# Get all current PR titles from GitHub
	local gh_prs
	gh_prs=$(get_review_prs | jq -r '.[].title | rtrimstr(" ") | ltrimstr(" ")')

	# Check all pending tasks and mark done if PR is not in GitHub results
	while read -r task_desc; do
		if ! echo "$gh_prs" | grep -Fxq "$task_desc"; then
			echo "Marking task as done: $task_desc"
			task_uuid=$(get_task_id_by_description "$task_desc")
			task "$task_uuid" done
		fi
	done < <(get_all_pending_pr_tasks)

	# Create new tasks for new PRs
	while read -r pr; do
		pr_title=$(echo "$pr" | jq -r '.title')
		pr_url=$(echo "$pr" | jq -r '.url')
		repo_name=$(echo "$pr" | jq -r '.repository.name')
		created_at=$(echo "$pr" | jq -r '.createdAt')
		updated_at=$(echo "$pr" | jq -r '.updatedAt')
		entry_ts=$(date -d "$created_at" +%s)
		task_uuid=$(get_task_id_by_description "$pr_title")
		if [[ -z "$task_uuid" ]]; then
			echo "Creating new task for PR: $pr_title"
			task_uuid=$(create_task "$pr_title" "entry:$entry_ts" "+pr" "+kill" "project:pr-reviews" "repo:$repo_name") || true
			annotate_task "$task_uuid" "$pr_url" || true
			notify "$pr_title" 0
			prs_added=$((prs_added + 1))
		else
			echo "Task already exists for PR: $pr_title"
		fi
	done < <(get_review_prs | jq -c '.[]')
}

main
