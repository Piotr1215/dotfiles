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

# Pending pr-reviews tasks, exported once per run. Every lookup below reads this
# in memory: each `task` call loads the whole 45k-task database, so a lookup per
# PR cost ~11 CPU-minutes per run. The cache is patched as tasks are created,
# renamed or completed, so lookups stay consistent with what the run has done.
PR_TASKS_JSON=""

load_pr_tasks() {
	PR_TASKS_JSON=$(task status:pending project:pr-reviews export)
	[ -n "$PR_TASKS_JSON" ] || PR_TASKS_JSON="[]"
}

# Drop a completed task from the cache.
pr_cache_remove() {
	PR_TASKS_JSON=$(jq -c --arg u "$1" 'map(select(.uuid != $u))' <<<"$PR_TASKS_JSON")
}

# Mirror a rename in the cache.
pr_cache_rename() {
	PR_TASKS_JSON=$(jq -c --arg u "$1" --arg d "$2" 'map(if .uuid == $u then .description = $d else . end)' <<<"$PR_TASKS_JSON")
}

# Add a freshly created task to the cache.
pr_cache_add() {
	PR_TASKS_JSON=$(jq -c --arg u "$1" --arg d "$2" --arg url "$3" --arg na "$4" \
		'. + [{uuid: $u, description: $d, annotations: [{description: $url}], tags: ["pr","kill","work"], new_activity: $na}]' <<<"$PR_TASKS_JSON")
}

# The first pending task with this description. Duplicates cannot be told apart
# by description, so the first one wins instead of a multi-line uuid.
get_task_id_by_description() {
	local description="$1"
	jq -r --arg desc "$description" 'first(.[] | select(.description == ($desc | rtrimstr(" ") | ltrimstr(" "))) | .uuid) // empty' <<<"$PR_TASKS_JSON"
}

# Find the pending pr-reviews task that tracks this PR URL. A PR keeps its URL
# across a retitle; its "title (#number)" description does not.
get_task_id_by_url() {
	local url="$1"
	jq -r --arg u "$url" '[.[] | select(any(.annotations[]?; .description == $u)) | .uuid][0] // empty' <<<"$PR_TASKS_JSON"
}

get_all_pending_pr_tasks() {
	jq -r '.[] | .description' <<<"$PR_TASKS_JSON"
}

get_review_prs() {
	# Query PRs where you're involved (author, assignee, commenter)
	local involved_prs
	involved_prs=$(gh search prs --involves Piotr1215 --owner loft-sh --state open --limit 1000 \
		--json title,url,number,repository,createdAt,updatedAt)

	# Query PRs where you're mentioned
	local mentioned_prs
	mentioned_prs=$(gh search prs --mentions Piotr1215 --owner loft-sh --state open --limit 1000 \
		--json title,url,number,repository,createdAt,updatedAt)

	# Query PRs you're requested to review (includes team requests)
	local review_prs
	review_prs=$(gh search prs --review-requested Piotr1215 --owner loft-sh --state open --limit 1000 \
		--json title,url,number,repository,createdAt,updatedAt)

	# Combine all results and remove duplicates
	jq -s '.[0] + .[1] + .[2] | group_by(.url) | map(.[0]) | sort_by(.updatedAt) | reverse' \
		<(echo "$involved_prs") <(echo "$mentioned_prs") <(echo "$review_prs")
}

get_approved_prs() {
	gh search prs --involves Piotr1215 --owner loft-sh --state open --review approved --limit 1000 \
		--json title,url,number --jq '.'
}

# Does this task currently carry the given tag?
task_has_tag() {
	local task_uuid="$1" tag="$2"
	jq -e --arg u "$task_uuid" --arg t "$tag" 'any(.[]; .uuid == $u and ((.tags // []) | index($t)))' <<<"$PR_TASKS_JSON" >/dev/null 2>&1
}

# Reconcile +pr_approved against the live approval state, in BOTH directions.
# GitHub dismisses an approval when a reviewer requests changes or, on many
# repos, when new commits land. An add-only sync leaves the tag behind after
# that, so a PR that now needs work keeps rendering as approved and drops out
# of view. The remove half is what makes the tag mean "approved right now"
# instead of "was approved at some point".
#
# Removing on absence is safe because the universe is already loft-sh scoped:
# main() completes any pr-reviews task whose PR is absent from the same
# --owner loft-sh query, so a task surviving to this point is always a PR that
# get_approved_prs would list if it were approved.
update_approved_status() {
	local approved_prs
	local task_uuid
	# main() passes --cached to reuse the run's task cache; a bare call reloads.
	[ "${1:-}" = "--cached" ] || load_pr_tasks
	approved_prs=$(get_approved_prs | jq -r '.[] | "\(.title) (#\(.number))" | rtrimstr(" ") | ltrimstr(" ")')
	while read -r task_desc; do
		[ -n "$task_desc" ] || continue
		task_uuid=$(get_task_id_by_description "$task_desc")
		[ -n "$task_uuid" ] || continue
		if echo "$approved_prs" | grep -Fxq "$task_desc"; then
			if ! task_has_tag "$task_uuid" pr_approved; then
				echo "Marking PR as approved: $task_desc"
				task "$task_uuid" modify +pr_approved
			fi
		elif task_has_tag "$task_uuid" pr_approved; then
			echo "Clearing stale approval: $task_desc"
			task "$task_uuid" modify -pr_approved
		fi
	done < <(get_all_pending_pr_tasks)
}

# Is the PR behind this task still open, asked of the PR itself?
# GitHub search can silently return a partial result set, and absence from one
# search is not proof the PR closed. Returns 0 (keep the task) when the PR is
# open or its state cannot be read, 1 when the task has no PR URL or the PR is
# closed or merged.
pr_still_open() {
	local task_uuid="$1" pr_url state
	pr_url=$(jq -r --arg u "$task_uuid" '[.[] | select(.uuid == $u) | .annotations[]?.description | select(test("^https://github.com/[^/]+/[^/]+/pull/[0-9]+$"))][0] // empty' <<<"$PR_TASKS_JSON")
	[ -n "$pr_url" ] || return 1
	state=$(gh pr view "$pr_url" --json state -q .state 2>/dev/null) || return 0
	[ "$state" = "OPEN" ]
}

main() {
	local pr_title pr_url repo_name task_uuid created_at entry_ts updated_at
	# Fetch once and use the same snapshot to complete and to create. Two fetches
	# disagreed often enough to complete and recreate ~50 tasks per run.
	local review_json gh_prs
	review_json=$(get_review_prs)
	load_pr_tasks
	gh_prs=$(echo "$review_json" | jq -r '.[] | "\(.title) (#\(.number))" | rtrimstr(" ") | ltrimstr(" ")')
	# Complete a pending task only when its PR is missing from the search AND
	# the PR itself is no longer open.
	while read -r task_desc; do
		if ! grep -Fxq -- "$task_desc" <<<"$gh_prs"; then
			task_uuid=$(get_task_id_by_description "$task_desc")
			[ -n "$task_uuid" ] || continue
			if pr_still_open "$task_uuid"; then
				continue
			fi
			echo "Marking task as done: $task_desc"
			task "$task_uuid" "done"
			pr_cache_remove "$task_uuid"
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
		# Renovate retitles on every version bump. Without the URL lookup each
		# retitle created a second task while the open PR kept the first alive.
		if [[ -z "$task_uuid" ]]; then
			task_uuid=$(get_task_id_by_url "$pr_url")
			if [[ -n "$task_uuid" ]]; then
				echo "PR retitled, renaming task: $pr_title"
				task "$task_uuid" modify "description:$pr_title" || true
				pr_cache_rename "$task_uuid" "$pr_title"
			fi
		fi
		if [[ -z "$task_uuid" ]]; then
			echo "Creating new task for PR: $pr_title"
			# new_activity is set at creation, without +fresh
			task_uuid=$(create_task "$pr_title" "entry:$entry_ts" "+pr" "+kill" "+work" "project:pr-reviews" "repo:$repo_name" "new_activity:$updated_at") || true
			annotate_task "$task_uuid" "$pr_url" || true
			[ -z "$task_uuid" ] || pr_cache_add "$task_uuid" "$pr_title" "$pr_url" "$updated_at"
		else
			# For existing tasks, compare the stored new_activity with the current updatedAt
			current_activity=$(jq -r --arg u "$task_uuid" 'first(.[] | select(.uuid == $u) | .new_activity) // empty' <<<"$PR_TASKS_JSON")
			if [ -n "$current_activity" ]; then
				current_activity_ts=$(date -d "$(format_date "$current_activity")" +%s)
			else
				current_activity_ts=0
			fi
			new_update_ts=$(date -d "$(format_date "$updated_at")" +%s)
			if [ "$new_update_ts" -gt "$current_activity_ts" ]; then
				echo "New activity detected for PR: $pr_title, marking as fresh"
				task "$task_uuid" modify "new_activity:$updated_at" +fresh || true
			elif [ "$new_update_ts" -ne "$current_activity_ts" ]; then
				# Stored value is newer than GitHub's; keep writing GitHub's value
				task "$task_uuid" modify "new_activity:$updated_at" || true
			fi
			echo "Task already exists for PR: $pr_title"
		fi
	done < <(echo "$review_json" | jq -c '.[]')
	# Update approved status for existing PRs
	update_approved_status --cached
}

main
