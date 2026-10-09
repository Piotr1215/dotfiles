#!/usr/bin/env bash
# Next blog post: rank the repos I worked on recently by how good a next post
# each would make. The decision is ~/.config/decide/next-blog.json, run by
# __decide.py (criteria, marks, record); this script holds the commands that
# decision file runs.
#
#   __next_blog.sh [-x N] [-k N] [-j] [DAYS]   rank repos with commits of mine
#                                              in the last DAYS (30); flags
#                                              as __decide.py
#   __next_blog.sh candidates                  each such repo as {name, text}
#   __next_blog.sh published                   every published title
#   __next_blog.sh liked                       the Medium posts readers
#                                              responded to most; fails
#                                              without a feedback file
#
# A repo's text is its name and my last 20 commit subjects. Candidates are the
# git repos directly under each NEXT_BLOG_ROOTS directory, or the directory
# itself when it is a repo (colon-separated, default ~/dev:~/.claude). The
# blog repo itself is no candidate. Published titles come from NEXT_BLOG_POSTS
# (default ~/dev/cloudrumble/blog), the Medium posts the site lists, and the
# feedback file. NEXT_BLOG_FEEDBACK (default ~/.local/share/next-blog/medium.tsv)
# holds one Medium post per line, "TITLE<TAB>COUNT", COUNT any engagement
# figure such as reads; the 10 highest are the posts readers responded to most.
set -eo pipefail

days="${NEXT_BLOG_DAYS:-30}"
posts="${NEXT_BLOG_POSTS:-$HOME/dev/cloudrumble/blog}"
feedback="${NEXT_BLOG_FEEDBACK:-${XDG_DATA_HOME:-$HOME/.local/share}/next-blog/medium.tsv}"
IFS=: read -ra roots <<<"${NEXT_BLOG_ROOTS:-$HOME/dev:$HOME/.claude}"
me="$(git config --global user.email || true)"

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

case "$1" in
candidates | published | liked) "$1" ;;
*)
	args=()
	while getopts 'x:k:j' opt; do
		case "$opt" in
		x | k) args+=("-$opt" "$OPTARG") ;;
		j) args+=(-j) ;;
		*)
			echo "usage: __next_blog.sh [-x N] [-k N] [-j] [DAYS] | candidates | published | liked" >&2
			exit 2
			;;
		esac
	done
	shift $((OPTIND - 1))
	export NEXT_BLOG_DAYS="${1:-30}"
	exec "$(dirname "$(realpath "$0")")/__decide.py" -d next-blog "${args[@]}" </dev/null
	;;
esac
