#!/usr/bin/env bash
set -eo pipefail
source /home/decoder/dev/dotfiles/scripts/__lib_taskwarrior_interop.sh

# Format a date string from "YYYYMMDDTHHMMSSZ" to "YYYY-MM-DDTHH:MM:SSZ"
format_date() {
	local date_str="$1"
	if [[ "$date_str" =~ ^([0-9]{4})([0-9]{2})([0-9]{2})T([0-9]{2})([0-9]{2})([0-9]{2})Z$ ]]; then
		echo "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}T${BASH_REMATCH[4]}:${BASH_REMATCH[5]}:${BASH_REMATCH[6]}Z"
	else
		echo "$date_str"
	fi
}

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
	# Query PRs where you're involved (author, assignee, commenter)
	local involved_prs
	involved_prs=$(gh search prs --involves Piotr1215 --owner loft-sh --state open --limit 100 \
		--json title,url,number,repository,createdAt,updatedAt)

	# Query PRs where you're mentioned
	local mentioned_prs
	mentioned_prs=$(gh search prs --mentions Piotr1215 --owner loft-sh --state open --limit 100 \
		--json title,url,number,repository,createdAt,updatedAt)

	# Query PRs you're requested to review (includes team requests)
	local review_prs
	review_prs=$(gh search prs --review-requested Piotr1215 --owner loft-sh --state open --limit 100 \
		--json title,url,number,repository,createdAt,updatedAt)

	# Combine all results and remove duplicates
	jq -s '.[0] + .[1] + .[2] | group_by(.url) | map(.[0]) | sort_by(.updatedAt) | reverse' \
		<(echo "$involved_prs") <(echo "$mentioned_prs") <(echo "$review_prs")
}

get_approved_prs() {
	gh search prs --involves Piotr1215 --owner loft-sh --state open --review approved --limit 100 \
		--json title,url,number --jq '.'
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

update_approved_status() {
	local approved_prs
	local task_uuid
	approved_prs=$(get_approved_prs | jq -r '.[] | "\(.title) (#\(.number))" | rtrimstr(" ") | ltrimstr(" ")')
	while read -r task_desc; do
		if echo "$approved_prs" | grep -Fxq "$task_desc"; then
			task_uuid=$(get_task_id_by_description "$task_desc")
			if [ -n "$task_uuid" ]; then
				echo "Marking PR as approved: $task_desc"
				task "$task_uuid" modify +pr_approved
			fi
		fi
	done < <(get_all_pending_pr_tasks)
}

main() {
	local pr_title pr_url repo_name task_uuid created_at entry_ts updated_at
	local prs_added=0
	# Get all current PR titles from GitHub
	local gh_prs
	gh_prs=$(get_review_prs | jq -r '.[] | "\(.title) (#\(.number))" | rtrimstr(" ") | ltrimstr(" ")')
	# Check all pending tasks and mark done if PR is not in GitHub results
	while read -r task_desc; do
		if ! echo "$gh_prs" | grep -Fxq "$task_desc"; then
			echo "Marking task as done: $task_desc"
			task_uuid=$(get_task_id_by_description "$task_desc")
			task "$task_uuid" done
		fi
	done < <(get_all_pending_pr_tasks)
	# Create new tasks for new PRs or update existing ones
	while read -r pr; do
		pr_title=$(echo "$pr" | jq -r '"\(.title) (#\(.number))"')
		pr_url=$(echo "$pr" | jq -r '.url')
		repo_name=$(echo "$pr" | jq -r '.repository.name')
		created_at=$(echo "$pr" | jq -r '.createdAt')
		updated_at=$(echo "$pr" | jq -r '.updatedAt')
		# Convert the creation date to a proper ISO8601 format and then to epoch
		entry_ts=$(date -d "$(format_date "$created_at")" +%s)
		task_uuid=$(get_task_id_by_description "$pr_title")
		if [[ -z "$task_uuid" ]]; then
			echo "Creating new task for PR: $pr_title"
			task_uuid=$(create_task "$pr_title" "entry:$entry_ts" "+pr" "+kill" "project:pr-reviews" "repo:$repo_name") || true
			annotate_task "$task_uuid" "$pr_url" || true
			# On task creation, record the new_activity without adding +fresh
			task "$task_uuid" modify "new_activity:$updated_at" || true
			notify "$pr_title"
			prs_added=$((prs_added + 1))
		else
			# For existing tasks, compare the stored new_activity with the current updatedAt
			current_activity=$(task "$task_uuid" export | jq -r '.[0].new_activity // empty')
			if [ -n "$current_activity" ]; then
				current_activity_ts=$(date -d "$(format_date "$current_activity")" +%s)
			else
				current_activity_ts=0
			fi
			new_update_ts=$(date -d "$(format_date "$updated_at")" +%s)
			if [ "$new_update_ts" -gt "$current_activity_ts" ]; then
				echo "New activity detected for PR: $pr_title, marking as fresh"
				task "$task_uuid" modify "new_activity:$updated_at" +fresh || true
			else
				task "$task_uuid" modify "new_activity:$updated_at" || true
			fi
			echo "Task already exists for PR: $pr_title"
		fi
	done < <(get_review_prs | jq -c '.[]')
	# Update approved status for existing PRs
	update_approved_status
}

main
