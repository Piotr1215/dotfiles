#!/usr/bin/env bash
# PROJECT: standup
# Answers the standup questions asked in #engineering-enablement-private.
#
# The standup used to be a form, so the session showed three panes of markdown
# and the form was filled from them. It is now a bot asking four questions in
# order, which wants a different shape: four blocks, each pasteable on its own,
# in the order it asks them.
#
# Blockers and handoffs have no source here. No task carries a blocked tag,
# dependencies are unused (task +BLOCKED count is 0), and inventing two tags
# that must be remembered every morning is how the standup timestamp knob ended
# up orphaned. Those two questions print their heading and get typed.
#
# Usage:
#   __standup_answers.sh          print every block
#   __standup_answers.sh --pick   choose a block, ctrl-y copies it

set -eo pipefail

SCRIPTS_DIR="${STANDUP_SCRIPTS_DIR:-/home/decoder/dev/dotfiles/scripts}"
COMPLETED_CMD="${STANDUP_COMPLETED_CMD:-$SCRIPTS_DIR/__list_completed_tasks_as_markdown.pl}"
TASKS_CMD="${STANDUP_TASKS_CMD:-$SCRIPTS_DIR/__list_tasks_as_markdown.pl}"
PRS_CMD="${STANDUP_PRS_CMD:-$SCRIPTS_DIR/__get_my_pending_prs.sh}"
CLIP_CMD="${STANDUP_CLIP_CMD:-xclip -selection clipboard}"

Q1="1. What did you accomplish yesterday?"
Q2="2. What are focusing on today?"
Q3="3. Do you have any blockers?"
Q4="4. Anything to hand off?"

# Days of completed work question 1 should cover. Monday reaches back across the
# weekend to Friday, every other day means yesterday. Same rule
# __list_tasks_as_markdown.pl:14 has used for years, rather than a second one.
standup_window_days() {
	local dow="${STANDUP_DOW:-$(date +%u)}"

	if [[ "$dow" == "1" ]]; then
		echo 3
	else
		echo 1
	fi
}

# Run a report, keeping its three outcomes distinct: content, nothing to report,
# and broken. Empty and broken render identically otherwise, which is precisely
# how this whole chain sat dead on a missing perl module without anyone seeing
# it.
render() {
	local label="$1"
	shift

	local out status
	set +e
	out="$("$@" 2>&1)"
	status=$?
	set -e

	if [[ $status -ne 0 ]]; then
		echo "($label unavailable: ${out%%$'\n'*})" >&2
		echo "($label unavailable, see stderr)"
		return 0
	fi

	# Trim leading and trailing whitespace so a report that emits only blank
	# lines is recognised as empty.
	out="${out#"${out%%[![:space:]]*}"}"
	out="${out%"${out##*[![:space:]]}"}"

	if [[ -z "$out" ]]; then
		echo "(nothing recorded)"
		return 0
	fi

	printf '%s\n' "$out"
}

# One file per question, so the picker can preview and copy a block whole.
build_blocks() {
	local dir="$1"
	local days
	days="$(standup_window_days)"

	{
		printf '%s\n\n' "$Q1"
		render "completed tasks" "$COMPLETED_CMD" "$days"
	} >"$dir/1"

	{
		printf '%s\n\n' "$Q2"
		render "current tasks" "$TASKS_CMD" "+current"
	} >"$dir/2"

	{
		printf '%s\n\n' "$Q3"
		printf '%s\n' "(type this one)"
	} >"$dir/3"

	{
		printf '%s\n\n' "$Q4"
		printf '%s\n' "(type this one; open PRs below are the usual handoff)"
		printf '\n'
		render "open PRs" "$PRS_CMD"
	} >"$dir/4"
}

print_all() {
	local dir="$1"
	local n

	for n in 1 2 3 4; do
		command cat "$dir/$n"
		[[ "$n" == "4" ]] || printf '\n%s\n\n' "----------------"
	done
}

# ctrl-y copies the focused block, the same binding every other picker in this
# repo uses.
pick_block() {
	local dir="$1"

	printf '%s\t%s\n' 1 "$Q1" 2 "$Q2" 3 "$Q3" 4 "$Q4" |
		fzf --delimiter='\t' \
			--with-nth=2 \
			--prompt='standup > ' \
			--preview="command cat $dir/{1}" \
			--preview-window='right:70%:wrap' \
			--bind="ctrl-y:execute-silent(command cat $dir/{1} | $CLIP_CMD)+change-prompt(copied > )" \
			>/dev/null
}

main() {
	local mode="${1:-print}"

	case "$mode" in
	print | --print) ;;
	--pick) mode="pick" ;;
	-h | --help)
		command sed -n '2,18p' "$0"
		exit 0
		;;
	*)
		echo "Unknown argument: $mode" >&2
		exit 1
		;;
	esac

	local dir
	dir="$(mktemp -d)"
	trap 'rm -rf "$dir"' EXIT

	build_blocks "$dir"

	if [[ "$mode" == "pick" ]]; then
		pick_block "$dir"
	else
		print_all "$dir"
	fi
}

main "$@"
