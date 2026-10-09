#!/usr/bin/env bash
# Next blog post: rank the repos I worked on recently by how good a next post
# each would make. classif rank asks every repo each question below; a repo's
# score is the product of the p of the answer each question wants.
#
#   __next_blog.sh [-k N] [-w] [DAYS]   rank repos with commits of mine in the
#                                       last DAYS (30); -k shows the top N, -w
#                                       marks the lines the top repo's answers
#                                       are most sensitive to
#   __next_blog.sh candidates           each such repo as {name, text}
#   __next_blog.sh published            every published title
#   __next_blog.sh liked                the Medium posts readers responded to
#                                       most; fails without a feedback file
#
# A repo's text is its name and my last 20 commit subjects. Candidates are the
# git repos directly under each NEXT_BLOG_ROOTS directory, or the directory
# itself when it is a repo (colon-separated, default ~/dev:~/.claude). The
# blog repo itself is no candidate. Published titles come from NEXT_BLOG_POSTS
# (default ~/dev/cloudrumble/blog), the Medium posts the site lists, and the
# feedback file. NEXT_BLOG_FEEDBACK (default ~/.local/share/next-blog/medium.tsv)
# holds one Medium post per line, "TITLE<TAB>COUNT", COUNT any engagement
# figure such as reads; the 10 highest are the posts readers responded to most.
# Without it, the liked question is not asked.
set -eo pipefail

days="${NEXT_BLOG_DAYS:-30}"
posts="${NEXT_BLOG_POSTS:-$HOME/dev/cloudrumble/blog}"
feedback="${NEXT_BLOG_FEEDBACK:-${XDG_DATA_HOME:-$HOME/.local/share}/next-blog/medium.tsv}"
IFS=: read -ra roots <<<"${NEXT_BLOG_ROOTS:-$HOME/dev:$HOME/.claude}"
me="$(git config --global user.email || true)"
blog="CloudRumble is a developer blog: hands-on posts about terminal workflows, Neovim, tmux, Kubernetes, homelab and local AI tooling that a reader can follow and reproduce."
# NAME, the answer that counts, QUESTION; each is asked with context_of NAME.
questions=(
	$'story\tyes\tDoes this work hold a story a developer could follow and reproduce in a hands-on blog post?'
	$'new\tno\tDoes one of the published posts already tell the story of this work?'
	$'liked\tyes\tIs this work on the same kind of topic as the posts readers responded to most?'
)

# Every git repo under the roots with commits of mine since DAYS ago.
active_repos() {
	local root repo
	for root in "${roots[@]}"; do
		if [[ -e "$root/.git" ]]; then
			echo "$root"
		else
			for repo in "$root"/*/; do
				if [[ -e "$repo/.git" ]]; then echo "${repo%/}"; fi
			done
		fi
	done | while read -r repo; do
		[[ "$(realpath "$repo")" == "$(realpath "$posts/.." 2>/dev/null)" ]] && continue
		if [[ -n "$(git -C "$repo" log -1 --since="$days days ago" --author="$me" --format=%h 2>/dev/null)" ]]; then
			echo "$repo"
		fi
	done
}

# Each active repo as one JSON line: its name and the text classif judges.
candidates() {
	local repo
	active_repos | while read -r repo; do
		jq -cn --arg name "$(basename "$repo")" --arg text "$(
			echo "Project: $(basename "$repo")"
			echo "Recent commits:"
			git -C "$repo" log --since="$days days ago" -n 20 --author="$me" --format='- %s'
		)" '{name: $name, text: $text}'
	done
}

# Every title already published: the blog, the Medium posts the site lists and
# the feedback file.
published() {
	local f
	echo "Published posts:"
	for f in "$posts"/*.md*; do
		[[ -f "$f" ]] && sed -n 's/^title: *"\{0,1\}\([^"]*\)"\{0,1\}$/- \1/p' "$f" | head -n 1
	done
	f="$posts/../src/data/blogs.json"
	[[ -f "$f" ]] && jq -r '.[].title | "- " + .' "$f"
	[[ -f "$feedback" ]] && cut -f1 "$feedback" | sed 's/^/- /'
	return 0
}

# The Medium posts readers responded to most.
liked() {
	[[ -s "$feedback" ]] || return 1
	echo "Medium posts readers responded to most:"
	sort -t $'\t' -k2,2nr "$feedback" | head -n 10 | cut -f1 | sed 's/^/- /'
}

# The context a question is asked with; fails when the question is not asked.
context_of() {
	case "$1" in
	story) echo "$blog" ;;
	new) published ;;
	liked) liked ;;
	esac
}

# Rank the active repos, best first: the questions, then a row per repo with
# the score and each answer with its p. -w adds the top repo's marks.
rank_repos() {
	local top="$1" mark="$2" cands q name want question table repo
	local -a asked=()
	local -A ctx=()
	cands="$(candidates)"
	if [[ -z "$cands" ]]; then
		echo "__next_blog.sh: no candidates: no repo has commits of mine in the last $days days" >&2
		return 1
	fi
	echo "Which recently active repo should the next CloudRumble post be about?"
	for q in "${questions[@]}"; do
		IFS=$'\t' read -r name want question <<<"$q"
		if ctx[$name]="$(context_of "$name")"; then
			asked+=("$q")
			printf '  %-5s  %-3s counts  %s\n' "$name" "$want" "$question"
		fi
	done
	echo
	table="$(for q in "${asked[@]}"; do
		IFS=$'\t' read -r name want question <<<"$q"
		classif rank -j "$question" -c "${ctx[$name]}" <<<"$cands" |
			jq -c --arg name "$name" --arg want "$want" '{name: $name, want: $want, ranking}'
	done | jq -rs --argjson top "${top:-0}" '
		(map({key: .name, value: (.ranking | map({key: .name, value: .}) | from_entries)}) | from_entries) as $a
		| map(.name) as $qs | (map({key: .name, value: .want}) | from_entries) as $want
		| (["score"] + $qs + ["repo"] | @tsv),
		  ([$a[$qs[0]] | keys_unsorted[] as $repo | select(all($qs[]; $a[.][$repo]))
		    | {repo: $repo, cells: [$qs[] | $a[.][$repo] | [.label, .p[.label]]],
		       score: (reduce $qs[] as $q (1; . * $a[$q][$repo].p[$want[$q]]))}]
		   | sort_by(-.score) | (if $top > 0 then .[:$top] else . end)[]
		   | [.score] + [.cells[] | "\(.[0]) \(.[1])"] + [.repo] | @tsv)' |
		awk -F '\t' -v OFS='\t' 'NR > 1 {
			$1 = sprintf("%.3f", $1)
			for (i = 2; i < NF; i++) { split($i, c, " "); $i = sprintf("%s %.3f", c[1], c[2]) }
		} 1' | column -t -s $'\t' -o '  ')"
	echo "$table"
	((mark)) || return 0
	repo="$(awk 'NR == 2 { print $NF }' <<<"$table")"
	echo
	echo "why $repo: the lines whose removal moves each answer's p most"
	for q in "${asked[@]}"; do
		IFS=$'\t' read -r name want question <<<"$q"
		echo "  $name, $want counts; + raised p(yes)"
		jq -c --arg repo "$repo" 'select(.name == $repo)' <<<"$cands" |
			classif rank -j -w "$question" -c "${ctx[$name]}" |
			jq -r '.ranking[0] | if .unmarked then "\tnot marked, \(.unmarked)"
				elif (.marks | length) == 0 then "\t(no single line moves it)"
				else .marks[] | "\(.delta)\t\(if .from == "context" then "context: " else "" end)\(.line)" end' |
			awk -F '\t' '$1 == "" { print "    " $2; next } { printf "    %+.3f  %s\n", $1, $2 }'
	done
}

case "$1" in
candidates | published | liked) "$1" ;;
*)
	top="" mark=0
	while getopts 'k:w' opt; do
		case "$opt" in
		k) top="$OPTARG" ;;
		w) mark=1 ;;
		*)
			echo "usage: __next_blog.sh [-k N] [-w] [DAYS] | candidates | published | liked" >&2
			exit 2
			;;
		esac
	done
	shift $((OPTIND - 1))
	days="${1:-$days}"
	rank_repos "$top" "$mark"
	;;
esac
