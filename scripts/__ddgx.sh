#!/usr/bin/env bash
# __ddgx.sh - DuckDuckGo search with readable page extracts.
#
# ddgr gives a list of titles and a two-line snippet. A text browser gives the
# whole page plus its navigation, cookie bar and footer. This sits between the
# two: ddgr finds the results, __readable.mjs renders each page to markdown,
# and you read that instead of loading the page.
#
# Extraction is Mozilla Readability plus Turndown, the same pair the
# MarkDownload extension composes, so output matches what the browser gives
# you. Run --setup once to install them into ~/.local/share/ddgx.
#
#   __ddgx.sh kubernetes finalizers stuck     # fzf picker, extract in preview
#   __ddgx.sh -d rust async traits            # dump mode, pipeable
#   __ddgx.sh -n 15 -d etcd defrag | less -R
#   __ddgx.sh site:kubernetes.io hpa          # ddgr syntax still works
#
# Keys in the picker. tab marks results, and every action below applies to the
# whole marked set, so mark five and hit one key:
#   tab      mark / unmark          enter   open in the browser
#   ctrl-o   read extracts in a pager
#   ctrl-e   open extracts in nvim as markdown notes (kept, re-openable)
#   ctrl-a   bookmark into pet-links.toml, the file plink writes
#   ctrl-y   copy the URLs          ctrl-r  re-fetch (bypass cache)
#   ctrl-d/u scroll the preview     ctrl-\  toggle the preview pane
#
# Env: DDGX_TTL (cache seconds, default 86400), DDGX_JOBS (prefetch
# concurrency, default 6), DDGX_NUM (default result count), DDGX_EDITOR
# (ctrl-e editor, default nvim), DDGX_PET_FILE (bookmark file).
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
READABLE="$SCRIPT_DIR/__readable.mjs"
MODULES_DIR="${DDGX_MODULES:-$HOME/.local/share/ddgx}"
# The MarkDownload settings export, stowed from .config/ddgx in this repo.
OPTIONS_FILE="${DDGX_OPTIONS:-${XDG_CONFIG_HOME:-$HOME/.config}/ddgx/markdownload-options.json}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/ddgx"
# Notes are durable: they live outside the cache so clearing extracts, or a
# stale-cache sweep, can never take hand-edited notes with them.
NOTES_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/ddgx/notes"
CACHE_TTL="${DDGX_TTL:-86400}"
FORCE_REFETCH=0
PET_LINKS="${DDGX_PET_FILE:-$HOME/dev/pet-snippets/pet-links.toml}"

# Print the header comment block: everything between the shebang and the first
# line of code, so the help text cannot drift out of sync with a line range.
usage() {
	sed -e '1d' -e '/^[^#]/,$d' "$SELF" | sed 's/^# \{0,1\}//'
}

die() {
	echo "$*" >&2
	exit 1
}

# Preserve the script's real exit status: a kill of an already-reaped prefetch
# would otherwise become the status the caller sees.
cleanup() {
	local status=$?
	[[ -n ${RESULTS_FILE:-} ]] && rm -f "$RESULTS_FILE"
	if [[ -n ${PREFETCH_PID:-} ]]; then
		kill "$PREFETCH_PID" 2>/dev/null || true
	fi
	exit "$status"
}

# Path of the extract cache entry for a URL.
cache_file() {
	local key
	key=$(printf '%s' "$1" | sha1sum | cut -d' ' -f1)
	printf '%s/%s.txt' "$CACHE_DIR" "$key"
}

# True when a cache entry exists and is within TTL. TTL of 0 never expires.
cache_fresh() {
	local file=$1 age
	if [[ $FORCE_REFETCH -eq 1 ]]; then
		return 1
	fi
	if [[ ! -s $file ]]; then
		return 1
	fi
	if [[ $CACHE_TTL -le 0 ]]; then
		return 0
	fi
	age=$(($(date +%s) - $(stat -c %Y "$file")))
	[[ $age -lt $CACHE_TTL ]]
}

# Extract a URL into the cache. Failures are not cached, so a site that was
# down or slow gets retried rather than remembered as empty.
extract_to_cache() {
	local url=$1 file tmp
	file=$(cache_file "$url")
	if cache_fresh "$file"; then
		return 0
	fi
	mkdir -p "$CACHE_DIR"
	tmp="$file.$$"
	if node "$READABLE" --url "$url" --stats >"$tmp" 2>/dev/null; then
		mv -f "$tmp" "$file"
		return 0
	fi
	rm -f "$tmp"
	return 1
}

# Install the extraction engine. Readability and Turndown are the pair the
# MarkDownload extension uses; they live outside the repo so 36MB of
# node_modules is never committed.
setup_engine() {
	command -v npm >/dev/null 2>&1 || die "npm not found: install node first"
	mkdir -p "$MODULES_DIR"
	(
		cd "$MODULES_DIR" || exit 1
		[[ -f package.json ]] || npm init -y >/dev/null 2>&1
		npm install --no-fund --no-audit \
			@mozilla/readability turndown turndown-plugin-gfm jsdom
	) || die "engine install failed"
	printf 'extraction engine installed in %s\n' "$MODULES_DIR"
	install_options
}

# The MarkDownload options page has an Export button. That export is what drives
# the markdown here, so the terminal and the browser button stay one setting
# rather than two that drift. The copy in the dotfiles is the durable one; this
# only imports a fresh export when you have just downloaded one.
install_options() {
	local newest
	newest=$(command ls -t "$HOME"/Downloads/MarkDownload-export-*.json 2>/dev/null | head -1)
	if [[ -z $newest ]]; then
		[[ -f $OPTIONS_FILE ]] ||
			printf 'no markdown settings found: using MarkDownload defaults\n'
		return 0
	fi
	mkdir -p "$(dirname "$OPTIONS_FILE")"
	cp "$newest" "$OPTIONS_FILE"
	printf 'markdown settings imported from %s\n' "$newest"
}

engine_ready() {
	[[ -d $MODULES_DIR/node_modules/@mozilla/readability ]]
}

# Field of the nth result in a results JSON file.
result_field() {
	jq -r --argjson i "$1" --arg f "$3" '.[$i][$f] // ""' "$2"
}

# Print text centred on a given width, with the colour applied after the
# padding is measured so escape codes never count toward the length.
center() {
	local cols=$1 text=$2 color=${3:-} pad
	pad=$(((cols - ${#text}) / 2))
	[[ $pad -lt 0 ]] && pad=0
	printf '%*s' "$pad" ''
	printf '%b%s\033[0m\n' "$color" "$text"
}

# The M-g popup opens at full size before there is anything to show. tmux
# cannot resize a popup or nest a smaller one inside it, so rather than leave a
# bare prompt in the corner of an empty pane, draw a search screen that fills
# it on purpose. Sets TYPED_QUERY.
prompt_for_query() {
	local rows cols pad i indent hint
	rows=$(tput lines 2>/dev/null || echo 24)
	cols=$(tput cols 2>/dev/null || echo 80)
	hint='tab mark  enter open  ctrl-o read  ctrl-e nvim  ctrl-a bookmark'
	clear 2>/dev/null || true

	local width fill
	width=$((cols - 8))
	[[ $width -gt 70 ]] && width=70
	[[ $width -lt 24 ]] && width=24
	indent=$(((cols - width) / 2))
	[[ $indent -lt 0 ]] && indent=0
	fill=$(printf '%*s' "$((width - 2))" '')
	fill=${fill// /─}

	pad=$(((rows - 7) / 2))
	for ((i = 0; i < pad; i++)); do printf '\n'; done

	center "$cols" 'duckduckgo results with the page text extracted' '\033[90m'
	printf '\n'

	# An input box drawn around the caret, so the popup reads as a search box
	# rather than a prompt adrift on an empty screen.
	printf '%*s\033[36m╭%s╮\033[0m\n' "$indent" '' "$fill"
	printf '%*s\033[36m│\033[0m\033[1;33m > \033[0m%*s\033[36m│\033[0m\n' \
		"$indent" '' "$((width - 5))" ''
	printf '%*s\033[36m╰%s╯\033[0m\n' "$indent" '' "$fill"
	printf '\n'
	center "$cols" "$hint" '\033[90m'

	# Back up into the box and read there. Four lines up from the cursor's
	# resting place below the hint: hint, blank, bottom border, input line.
	printf '\033[4A'
	printf '\033[%dG' "$((indent + 5))"
	TYPED_QUERY=''
	read -r -e TYPED_QUERY || return 1
	clear 2>/dev/null || true
}

hrule() {
	local width=$1
	printf '\033[90m'
	printf '%.0s─' $(seq 1 "$width")
	printf '\033[0m\n'
}

# ---------------------------------------------------------------------------
# Internal modes, invoked by the picker's key bindings.
# ---------------------------------------------------------------------------

mode_preview() {
	local file=$1 idx=$2 width url title abstract cached
	width=$((${FZF_PREVIEW_COLUMNS:-100} - 2))
	[[ $width -lt 40 ]] && width=40

	url=$(result_field "$idx" "$file" url)
	title=$(result_field "$idx" "$file" title)
	abstract=$(result_field "$idx" "$file" abstract)

	printf '\033[1;36m%s\033[0m\n' "$title"
	printf '\033[33m%s\033[0m\n\n' "$url"
	if [[ -n $abstract ]]; then
		printf '\033[90m%s\033[0m\n\n' "$(printf '%s' "$abstract" | fold -s -w "$width")"
	fi
	hrule "$width"
	printf '\n'

	cached=$(cache_file "$url")
	if extract_to_cache "$url"; then
		# The extract ends on its last character, the way the extension writes
		# its files, and carries no escape codes so it opens clean in an
		# editor. Terminating the line and dimming the footer is this end's
		# job, not the file's.
		sed $'s/^\\[kept .* characters of page text\\]$/\033[90m&\033[0m/' "$cached"
		printf '\n'
	else
		printf '\033[31m(no page text: fetch blocked, timed out, or the page needs JavaScript)\033[0m\n'
	fi
}

# Write "# title / Source: url / extract" for one result to stdout.
emit_note() {
	local file=$1 idx=$2 url title cached
	url=$(result_field "$idx" "$file" url)
	title=$(result_field "$idx" "$file" title)
	extract_to_cache "$url" || true
	cached=$(cache_file "$url")

	printf '# %s\n\n' "$title"
	printf 'Source: %s\n\n' "$url"
	if [[ -s $cached ]]; then
		cat "$cached"
		printf '\n'
	else
		printf '(no page text extracted)\n'
	fi
}

# The read/copy/edit modes take every marked result, so tab-marking a handful
# and hitting one key acts on the whole set rather than the focused row.
mode_read() {
	local file=$1 idx combined
	shift
	combined=$(mktemp -t ddgx-read-XXXXXX.md)
	for idx in "$@"; do
		emit_note "$file" "$idx" >>"$combined"
		printf '\n\n---\n\n' >>"$combined"
	done
	if command -v bat >/dev/null 2>&1; then
		bat --style=plain --language=markdown --paging=always "$combined"
	else
		less -R "$combined"
	fi
	rm -f "$combined"
}

mode_copy() {
	local file=$1 idx urls=()
	shift
	for idx in "$@"; do
		urls+=("$(result_field "$idx" "$file" url)")
	done
	local payload
	payload=$(printf '%s\n' "${urls[@]}")
	if command -v wl-copy >/dev/null 2>&1 && [[ -n ${WAYLAND_DISPLAY:-} ]]; then
		printf '%s' "$payload" | wl-copy
	elif command -v xclip >/dev/null 2>&1; then
		printf '%s' "$payload" | xclip -selection clipboard
	elif command -v xsel >/dev/null 2>&1; then
		printf '%s' "$payload" | xsel --clipboard --input
	fi
}

# Write the note unless it holds edits worth protecting.
#
# A note you have typed into is yours and never gets overwritten. One you only
# ever read is regenerated, because otherwise the first scaffold is frozen
# forever: a page that was down at the time, or an extract from an older
# engine, would keep opening in the editor long after the cache was right.
# The record of what was scaffolded is a checksum kept beside the notes.
scaffold_note() {
	local file=$1 idx=$2 note=$3 stamp
	stamp="$NOTES_DIR/.scaffold/$(basename "$note").sha1"
	mkdir -p "$(dirname "$stamp")"

	if [[ -f $note ]]; then
		# No checksum means the file is not ours to rewrite.
		[[ -f $stamp ]] || return 0
		sha1sum --status -c "$stamp" 2>/dev/null || return 0
	fi
	emit_note "$file" "$idx" >"$note"
	sha1sum "$note" >"$stamp"
}

# Open the extracts as markdown notes, kept in a durable directory so anything
# worth editing survives the search that produced it.
mode_edit() {
	local file=$1 idx title slug note notes=() editor
	shift
	mkdir -p "$NOTES_DIR"
	for idx in "$@"; do
		# An index past the end of the results would otherwise leave an empty
		# note behind in a directory that is meant to be durable.
		[[ -n $(result_field "$idx" "$file" url) ]] || continue
		title=$(result_field "$idx" "$file" title)
		slug=$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' |
			sed 's/[^a-z0-9]\+/-/g; s/^-//; s/-$//' | cut -c1-60)
		[[ -z $slug ]] && slug="result-$idx"
		note="$NOTES_DIR/$slug.md"
		scaffold_note "$file" "$idx" "$note"
		notes+=("$note")
	done

	editor=${DDGX_EDITOR:-}
	if [[ -z $editor ]]; then
		if command -v nvim >/dev/null 2>&1; then
			editor=nvim
		else
			editor=${EDITOR:-vi}
		fi
	fi
	"$editor" "${notes[@]}"
}

# Bookmark into the same pet snippet file the plink zsh function writes, and
# through pet itself rather than by appending TOML, so the file keeps exactly
# one writer and one format. Values travel in the environment: an expect
# heredoc that interpolated a page title would break on the first quote.
mode_bookmark() {
	local file=$1 idx url title
	shift
	for idx in "$@"; do
		url=$(result_field "$idx" "$file" url)
		title=$(result_field "$idx" "$file" title)
		[[ -z $url ]] && continue
		if [[ -f $PET_LINKS ]] && grep -qF "xdg-open $url" "$PET_LINKS"; then
			continue # already bookmarked
		fi
		PET_FILE="$PET_LINKS" PET_CMD="xdg-open $url" PET_DESC="Link to $title" \
			expect >/dev/null 2>&1 <<-'EXPECT'
			spawn env PET_SNIPPET_FILE=$env(PET_FILE) pet new -t
			expect "Command>"
			send "$env(PET_CMD)\r"
			expect "Description>"
			send "$env(PET_DESC)\r"
			expect "Tag>"
			send "link\r"
			expect eof
		EXPECT
	done
}

mode_refetch() {
	local file=$1 idx url
	shift
	for idx in "$@"; do
		url=$(result_field "$idx" "$file" url)
		rm -f "$(cache_file "$url")"
		extract_to_cache "$url" || true
	done
}

mode_open() {
	local url=$1
	if [[ -n ${BROWSER:-} ]] && command -v "$BROWSER" >/dev/null 2>&1; then
		nohup "$BROWSER" "$url" >/dev/null 2>&1 &
	else
		nohup xdg-open "$url" >/dev/null 2>&1 &
	fi
}

# ---------------------------------------------------------------------------
# Main modes.
# ---------------------------------------------------------------------------

# Warm the cache for every result at once, so previews are instant instead of
# blocking on a fetch each time the selection moves.
prefetch() {
	local file=$1 url
	if [[ $FORCE_REFETCH -eq 1 ]]; then
		while IFS= read -r url; do
			[[ -n $url ]] && rm -f "$(cache_file "$url")"
		done < <(jq -r '.[].url' "$file")
	fi
	# One node process for the whole result set: eight separate runs would pay
	# the jsdom import eight times over.
	node "$READABLE" --batch "$file" --cache "$CACHE_DIR" --stats \
		>/dev/null 2>&1 &
	PREFETCH_PID=$!
}

mode_dump() {
	local file=$1 count width lines i url title abstract cached
	count=$(jq 'length' "$file")
	width=${DUMP_WIDTH:-100}
	lines=$DUMP_LINES

	prefetch "$file"
	wait "$PREFETCH_PID" 2>/dev/null || true

	for ((i = 0; i < count; i++)); do
		url=$(result_field "$i" "$file" url)
		title=$(result_field "$i" "$file" title)
		abstract=$(result_field "$i" "$file" abstract)

		printf '\033[1;36m%d. %s\033[0m\n' "$((i + 1))" "$title"
		printf '   \033[33m%s\033[0m\n' "$url"
		if [[ -n $abstract ]]; then
			printf '%s\n' "$abstract" | fold -s -w "$((width - 3))" | sed 's/^/   /'
		fi
		printf '\n'

		cached=$(cache_file "$url")
		if [[ -s $cached ]]; then
			head -n "$lines" "$cached" | sed 's/^/   /'
			if [[ $(wc -l <"$cached") -gt $lines ]]; then
				printf '   \033[90m...\033[0m\n'
			fi
		else
			printf '   \033[31m(no page text)\033[0m\n'
		fi
		printf '\n'
	done
}

mode_pick() {
	local file=$1 count selected line idx url
	count=$(jq 'length' "$file")

	prefetch "$file"

	selected=$(
		jq -r 'to_entries[] | "\(.key)\t\(.value.title)\t\(.value.url)"' "$file" |
			awk -F'\t' '{
				split($3, parts, "/")
				printf "%s\t%2d. %s  \033[90m[%s]\033[0m\n", $1, $1 + 1, $2, parts[3]
			}' |
			fzf --ansi --multi \
				--delimiter=$'\t' --with-nth=2.. \
				--prompt='result > ' \
				--header="tab mark · enter open · ctrl-o read · ctrl-e nvim · ctrl-a bookmark · ctrl-y copy · ctrl-r refetch" \
				--preview="$SELF --preview '$file' {1}" \
				--preview-window='right,58%,wrap,border-left' \
				--bind="ctrl-o:execute($SELF --read '$file' {+1})" \
				--bind="ctrl-e:execute($SELF --edit '$file' {+1})" \
				--bind="ctrl-a:execute-silent($SELF --bookmark '$file' {+1})+change-header(bookmarked to pet-links.toml · tab mark · enter open · ctrl-o read · ctrl-e nvim · ctrl-y copy)" \
				--bind="ctrl-y:execute-silent($SELF --copy '$file' {+1})" \
				--bind="ctrl-r:execute-silent($SELF --refetch '$file' {+1})+refresh-preview" \
				--bind='ctrl-\:change-preview-window(hidden|right,58%,wrap,border-left)' \
				--bind='ctrl-d:preview-half-page-down' \
				--bind='ctrl-u:preview-half-page-up' || true
	)

	[[ -z $selected ]] && return 0

	while IFS= read -r line; do
		idx=${line%%$'\t'*}
		url=$(result_field "$idx" "$file" url)
		[[ -n $url ]] && mode_open "$url"
	done <<<"$selected"
}

# ---------------------------------------------------------------------------

main() {
	local num="${DDGX_NUM:-8}" dump=0 args=()
	DUMP_LINES=12

	# Internal modes come first: they are re-entrant calls from fzf bindings.
	# Internal modes take the results file, then every marked index.
	case "${1:-}" in
	--preview)
		shift
		mode_preview "$@"
		return 0
		;;
	--read)
		shift
		mode_read "$@"
		return 0
		;;
	--copy)
		shift
		mode_copy "$@"
		return 0
		;;
	--edit)
		shift
		mode_edit "$@"
		return 0
		;;
	--bookmark)
		shift
		mode_bookmark "$@"
		return 0
		;;
	--refetch)
		shift
		mode_refetch "$@"
		return 0
		;;
	--fetch)
		extract_to_cache "$2" || true
		return 0
		;;
	--setup)
		setup_engine
		return 0
		;;
	esac

	while [[ $# -gt 0 ]]; do
		case "$1" in
		-h | --help)
			usage
			return 0
			;;
		-n | --num)
			num=$2
			shift 2
			;;
		-d | --dump)
			dump=1
			shift
			;;
		-l | --lines)
			DUMP_LINES=$2
			shift 2
			;;
		--no-cache)
			FORCE_REFETCH=1
			shift
			;;
		--)
			shift
			args+=("$@")
			break
			;;
		*)
			args+=("$1")
			shift
			;;
		esac
	done

	if [[ ${#args[@]} -eq 0 ]]; then
		if [[ ! -t 0 ]]; then
			usage
			return 1
		fi
		# Started with no query, which is how the tmux M-g popup launches it.
		prompt_for_query || return 0
		if [[ -z ${TYPED_QUERY//[[:space:]]/} ]]; then
			return 0
		fi
		args=("$TYPED_QUERY")
	fi

	command -v ddgr >/dev/null 2>&1 || die "ddgr not found"
	command -v jq >/dev/null 2>&1 || die "jq not found"
	command -v node >/dev/null 2>&1 || die "node not found"
	[[ -f $READABLE ]] || die "missing extractor: $READABLE"
	engine_ready || die "extraction engine missing: run ${SELF##*/} --setup"

	RESULTS_FILE=$(mktemp -t ddgx-results-XXXXXX.json)
	trap cleanup EXIT INT TERM

	# The query round-trip is the one unavoidable wait, so say it is happening
	# instead of leaving a blank screen.
	if [[ -t 1 ]]; then
		printf '\033[90m  searching for %s ...\033[0m\r' "${args[*]}" >&2
	fi
	if ! ddgr --json --num "$num" --noprompt "${args[@]}" >"$RESULTS_FILE" 2>/dev/null; then
		die "search failed"
	fi
	if [[ -t 1 ]]; then
		printf '\033[2K\r' >&2
	fi
	if [[ ! -s $RESULTS_FILE ]] || [[ $(jq 'length' "$RESULTS_FILE") -eq 0 ]]; then
		die "No results."
	fi

	if [[ $dump -eq 1 ]] || [[ ! -t 1 ]]; then
		# Piped without -d: dump rather than start fzf on a headless stdout.
		mode_dump "$RESULTS_FILE"
	else
		mode_pick "$RESULTS_FILE"
	fi
}

main "$@"
