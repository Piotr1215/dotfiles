#!/usr/bin/env bash
# Next blog post: rank the repos I worked on recently by how good a next post
# each would make, so the choice is mine with the evidence in front of me.
#
#   __next_blog.sh [-x N] [DAYS]    repos with commits of mine in the last DAYS (30)
#
# A small local model is good at one yes/no claim about one text and poor at a
# many-way pick, so classif asks each repo's recent commit subjects separate
# questions, the criteria, and the score is the product of the answers:
#   story  p(yes) the work holds a story a developer can follow and reproduce
#   new    p(no)  a published post already tells it
#   liked  p(yes) it is on the kind of topic readers responded to most on Medium
# liked is asked only when the feedback file exists. Prints one row per repo,
# best first. A repo classif cannot score is left out with a note on stderr.
# Exit 1 when nothing could be ranked.
#
# Marks: for the top N repos (-x, default 1, 0 for none) each line of the text
# is dropped in turn and every criterion asked again. The lines whose removal
# moves p most are the ones the answer rests on: + raised the score, - lowered
# it. They come from the same one-call reading as the answer, so they cannot
# disagree with it the way classif --why's line-by-line reading can. About one
# call per line per criterion: 20 commits and two criteria take a minute.
#
# Record: every run writes the criteria with their context, each repo's text,
# every p and the marks to $XDG_STATE_HOME/next-blog/DATE.json and names the
# file on stderr, so a decision can be read back and rerun.
#
# Candidates are the git repos directly under each NEXT_BLOG_ROOTS directory,
# or the directory itself when it is a repo (colon-separated, default
# ~/dev:~/.claude). The blog repo itself is no candidate. Published titles come
# from NEXT_BLOG_POSTS (default ~/dev/cloudrumble/blog), the Medium posts the
# site lists, and the feedback file. NEXT_BLOG_FEEDBACK (default
# ~/.local/share/next-blog/medium.tsv) holds one Medium post per line,
# "TITLE<TAB>COUNT", COUNT any engagement figure such as reads; the 10 highest
# are the posts readers responded to most.
set -eo pipefail

explain=1
while getopts 'x:' opt; do
	case "$opt" in
	x) explain="$OPTARG" ;;
	*)
		echo "usage: __next_blog.sh [-x N] [DAYS]" >&2
		exit 2
		;;
	esac
done
shift $((OPTIND - 1))

days="${1:-30}"
posts="${NEXT_BLOG_POSTS:-$HOME/dev/cloudrumble/blog}"
feedback="${NEXT_BLOG_FEEDBACK:-${XDG_DATA_HOME:-$HOME/.local/share}/next-blog/medium.tsv}"
records="${XDG_STATE_HOME:-$HOME/.local/state}/next-blog"
IFS=: read -ra roots <<<"${NEXT_BLOG_ROOTS:-$HOME/dev:$HOME/.claude}"
me="$(git config --global user.email || true)"
blog_about="CloudRumble is a developer blog: hands-on posts about terminal workflows, Neovim, tmux, Kubernetes, homelab and local AI tooling that a reader can follow and reproduce."

# Every git repo under the roots with commits of mine since DAYS ago.
active_repos() {
	local root repo
	for root in "${roots[@]}"; do
		if [[ -e "$root/.git" ]]; then
			echo "$root"
		else
			for repo in "$root"/*/; do
				[[ -e "$repo/.git" ]] && echo "${repo%/}"
			done
		fi
	done | while read -r repo; do
		[[ "$(realpath "$repo")" == "$(realpath "$posts/.." 2>/dev/null)" ]] && continue
		[[ -n "$(git -C "$repo" log -1 --since="$days days ago" --author="$me" --format=%h 2>/dev/null)" ]] && echo "$repo"
	done
	return 0
}

# What classif judges for one repo: its name and recent commit subjects.
work() {
	echo "Project: $(basename "$1")"
	echo "Recent commits:"
	git -C "$1" log --since="$days days ago" -n 20 --author="$me" --format='- %s'
}

# Every title already published: the blog, the Medium posts the site lists and
# the feedback file.
published() {
	local f
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
	sort -t $'\t' -k2,2nr "$feedback" | head -n 10 | cut -f1 | sed 's/^/- /'
}

# p of criterion $1 for the text on stdin. Fails when classif cannot score it.
ask() {
	local out
	out="$(classif -j -c "${crit_ctx[$1]}" "${crit_q[$1]}" 2>/dev/null)" || [[ $? -eq 1 ]] || return 2
	jq -er --arg l "${crit_want[$1]}" '.p[$l]' <<<"$out"
}

# Each criterion's p for every active repo, as one JSON object per line.
score_repos() {
	local repo text p ps i
	while read -r repo; do
		text="$(work "$repo")"
		ps="{}"
		for i in "${!crit_name[@]}"; do
			if ! p="$(ask "$i" <<<"$text")"; then
				echo "next-blog: classif could not score $(basename "$repo")" >&2
				continue 2
			fi
			ps="$(jq -c --arg k "${crit_name[i]}" --argjson v "$p" '.[$k] = $v' <<<"$ps")"
		done
		jq -cn --arg repo "$(basename "$repo")" --arg text "$text" --argjson p "$ps" \
			'{repo: $repo, score: (reduce $p[] as $v (1; . * $v)), p: $p, text: $text}'
	done <<<"$1"
}

# The ranking with marks added to its first $explain entries: per criterion,
# up to three lines whose removal moves p by 0.005 or more, most first, as
# {line, delta}, delta being p with the line minus p without it.
mark() {
	local ranking="$1" r i l text full p marks
	local -a lines
	for ((r = 0; r < explain && r < $(jq length <<<"$ranking"); r++)); do
		text="$(jq -r ".[$r].text" <<<"$ranking")"
		mapfile -t lines <<<"$text"
		for i in "${!crit_name[@]}"; do
			full="$(jq ".[$r].p.${crit_name[i]}" <<<"$ranking")"
			marks="[]"
			for l in "${!lines[@]}"; do
				[[ "${lines[l]}" == "Recent commits:" ]] && continue
				p="$(printf '%s\n' "${lines[@]:0:l}" "${lines[@]:l+1}" | ask "$i")" || continue
				marks="$(jq -c --arg line "${lines[l]}" --argjson full "$full" --argjson p "$p" \
					'. + [{line: $line, delta: ($full - $p)}]' <<<"$marks")"
			done
			ranking="$(jq -c --argjson r "$r" --arg k "${crit_name[i]}" --argjson m "$marks" \
				'.[$r].marks[$k] = ($m | map(select((if .delta < 0 then -.delta else .delta end) >= 0.005))
					| sort_by(-(if .delta < 0 then -.delta else .delta end)) | .[:3])' <<<"$ranking")"
		done
	done
	echo "$ranking"
}

# The ranking as a table, then the marks of each marked repo.
report() {
	{
		printf 'score\t%s\trepo\n' "$(
			IFS=$'\t'
			echo "${crit_name[*]}"
		)"
		jq -r --args '.[] | [.score] + [.p[$ARGS.positional[]]] + [.repo] | @tsv' "${crit_name[@]}" <<<"$1" |
			awk -F'\t' -v OFS='\t' '{ $1 = sprintf("%.3f", $1); print }'
	} | column -t -s $'\t'
	jq -r '.[] | select(.marks) | "\nwhy \(.repo): lines whose removal moves the answer most",
		(.marks | to_entries[] | "  \(.key)",
			if .value == [] then "    (no single line moves it)" else (.value[] | "    \(.delta)\t\(.line)") end)' <<<"$1" |
		awk -F'\t' 'NF == 2 { printf "    %+.3f  %s\n", $1, $2; next } { print }'
}

main() {
	local repos ranking told_ctx liked_ctx criteria record i
	repos="$(active_repos)"
	if [[ -z "$repos" ]]; then
		echo "next-blog: no repo has commits in the last $days days" >&2
		exit 1
	fi
	told_ctx="$(printf '%s\nPublished posts:\n%s' "$blog_about" "$(published)")"
	crit_name=(story new)
	crit_want=(yes no)
	crit_q=("Does this work hold a story a developer could follow and reproduce in a hands-on blog post?"
		"Does one of the published posts already tell the story of this work?")
	crit_ctx=("$blog_about" "$told_ctx")
	if [[ -s "$feedback" ]]; then
		liked_ctx="$(printf 'Medium posts readers responded to most:\n%s' "$(liked)")"
		crit_name+=(liked)
		crit_want+=(yes)
		crit_q+=("Is this work on the same kind of topic as the posts readers responded to most?")
		crit_ctx+=("$liked_ctx")
	fi

	ranking="$(score_repos "$repos" | jq -sc 'sort_by(-.score)')"
	[[ "$(jq length <<<"$ranking")" -gt 0 ]] || exit 1
	ranking="$(mark "$ranking")"
	report "$ranking"

	criteria="[]"
	for i in "${!crit_name[@]}"; do
		criteria="$(jq -c --arg n "${crit_name[i]}" --arg w "${crit_want[i]}" --arg q "${crit_q[i]}" --arg c "${crit_ctx[i]}" \
			'. + [{name: $n, want: $w, question: $q, context: $c}]' <<<"$criteria")"
	done
	mkdir -p "$records"
	record="$records/$(date +%FT%H%M%S).json"
	jq --arg date "$(date -Iseconds)" --arg days "$days" --argjson criteria "$criteria" \
		'{date: $date, days: ($days | tonumber), criteria: $criteria, ranking: .}' <<<"$ranking" >"$record"
	echo "next-blog: record in $record" >&2
}

main
