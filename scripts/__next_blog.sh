#!/usr/bin/env bash
# Next blog post: rank the repos I worked on recently by how good a next post
# each would make, so the choice is mine with the evidence in front of me.
#
#   __next_blog.sh [DAYS]    repos with commits of mine in the last DAYS (30)
#
# A small local model is good at one yes/no claim about one text and poor at a
# many-way pick, so classif asks each repo's recent commit subjects three
# separate questions and the script multiplies the answers:
#   story  p(yes) the work holds a story a developer can follow and reproduce
#   new    p(no)  a published post already tells it
#   liked  p(yes) it is on the kind of topic readers responded to most on Medium
# Prints one row per repo, best first: score story new liked repo. liked shows
# "-" and counts as 1 without a feedback file. A repo classif cannot score is
# left out with a note on stderr. Exit 1 when nothing could be ranked.
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

days="${1:-30}"
posts="${NEXT_BLOG_POSTS:-$HOME/dev/cloudrumble/blog}"
feedback="${NEXT_BLOG_FEEDBACK:-${XDG_DATA_HOME:-$HOME/.local/share}/next-blog/medium.tsv}"
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

# p of one label for a yes/no question about a repo's work. Fails when classif
# cannot score it.
ask() {
	local repo="$1" label="$2" ctx="$3" question="$4" out
	out="$(work "$repo" | classif -j -c "$ctx" "$question" 2>/dev/null)" || [[ $? -eq 1 ]] || return 2
	jq -er --arg l "$label" '.p[$l]' <<<"$out"
}

main() {
	local repos repo story new like rows="" told_ctx liked_ctx=""
	repos="$(active_repos)"
	if [[ -z "$repos" ]]; then
		echo "next-blog: no repo has commits in the last $days days" >&2
		exit 1
	fi
	told_ctx="$(printf '%s\nPublished posts:\n%s' "$blog_about" "$(published)")"
	[[ -s "$feedback" ]] && liked_ctx="$(printf 'Medium posts readers responded to most:\n%s' "$(liked)")"

	while read -r repo; do
		like=-
		if ! story="$(ask "$repo" yes "$blog_about" "Does this work hold a story a developer could follow and reproduce in a hands-on blog post?")" ||
			! new="$(ask "$repo" no "$told_ctx" "Does one of the published posts already tell the story of this work?")" ||
			{ [[ -n "$liked_ctx" ]] && ! like="$(ask "$repo" yes "$liked_ctx" "Is this work on the same kind of topic as the posts readers responded to most?")"; }; then
			echo "next-blog: classif could not score $(basename "$repo")" >&2
			continue
		fi
		rows+="$(awk -v s="$story" -v n="$new" -v l="$like" -v r="$(basename "$repo")" \
			'BEGIN { printf "%.3f\t%s\t%s\t%s\t%s", s * n * (l == "-" ? 1 : l), s, n, l, r }')"$'\n'
	done <<<"$repos"

	[[ -n "$rows" ]] || exit 1
	{
		printf 'score\tstory\tnew\tliked\trepo\n'
		sort -t $'\t' -k1,1nr <<<"${rows%$'\n'}"
	} | column -t -s $'\t'
}

main
