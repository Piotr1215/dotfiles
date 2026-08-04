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
#   ctrl-s   refine the query       ctrl-\  toggle the preview pane
#   ctrl-d/u scroll the preview
#
# ctrl-s builds the query instead of asking you to recall the syntax. Pick an
# operator, fill in its value, and the search re-runs under the picker. site:
# offers the domains the current results came from, filetype: offers a list,
# and an operator already in the query arrives prefilled so narrowing it is an
# edit. The raw query stays editable from the same menu, and a refinement that
# finds nothing leaves the previous results standing.
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
PICKER_KEYS='tab mark · enter open · ctrl-o read · ctrl-e nvim · ctrl-a bookmark · ctrl-y copy · ctrl-r refetch · ctrl-s refine'

# Print the header comment block: everything between the shebang and the first
# line of code, so the help text cannot drift out of sync with a line range.
usage() {
	sed -e '1d' -e '/^[^#]/,$d' "$SELF" | sed 's/^# \{0,1\}//'
}

# A message printed into the M-g popup is gone the instant the process ends,
# and a popup that opens and closes reads as one that never opened. When the
# query came from the popup's own search box, hold the message on screen.
die() {
	printf '%s\n' "$*" >&2
	if [[ ${POPUP_MODE:-0} -eq 1 && -e /dev/tty ]]; then
		printf '\n\033[90mpress any key\033[0m' >&2
		read -rsn1 </dev/tty || true
	fi
	exit 1
}

# Run one search. ddgr answers a throttled or refused request with an empty
# set, exit 0, and the reason on stderr: keeping that reason is the difference
# between "nobody has written this page" and "DuckDuckGo turned us away", and
# without it the tool blames the query for the network's answer. Sets
# SEARCH_ERROR and returns non-zero when nothing usable came back.
search_ddgr() {
	local out=$1 num=$2 query=$3 err count rc=0
	err=$(mktemp -t ddgx-err-XXXXXX)
	SEARCH_ERROR=''
	ddgr --json --num "$num" --noprompt "$query" >"$out" 2>"$err" || rc=$?
	count=$(jq 'length' "$out" 2>/dev/null || printf '0')
	if [[ $rc -eq 0 && -n $count && $count -gt 0 ]]; then
		rm -f "$err"
		return 0
	fi
	SEARCH_ERROR=$(head -1 "$err" 2>/dev/null || true)
	SEARCH_ERROR=${SEARCH_ERROR#\[ERROR\] }
	[[ -z $SEARCH_ERROR ]] && SEARCH_ERROR='no results'
	rm -f "$err"
	return 1
}

# Preserve the script's real exit status: a kill of an already-reaped prefetch
# would otherwise become the status the caller sees.
cleanup() {
	local status=$?
	if [[ -n ${TTY_STATE:-} ]]; then
		stty "$TTY_STATE" </dev/tty 2>/dev/null || true
	fi
	if [[ -n ${RESULTS_FILE:-} ]]; then
		rm -f "$RESULTS_FILE" "$(query_file "$RESULTS_FILE")" \
			"$(note_file "$RESULTS_FILE")" "$RESULTS_FILE.new"
	fi
	if [[ -n ${PREFETCH_PID:-} ]]; then
		kill "$PREFETCH_PID" 2>/dev/null || true
	fi
	exit "$status"
}

# The live query and any one-line message live beside the results file. A
# refinement runs as its own process, so a file is what it has to hand the
# picker back its new state through.
query_file() { printf '%s.query' "$1"; }
note_file() { printf '%s.note' "$1"; }

current_query() {
	local qf
	qf=$(query_file "$1")
	[[ -s $qf ]] && head -n1 "$qf"
	return 0
}

set_note() { printf '%s\n' "$2" >"$(note_file "$1")"; }

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
	EXTRACT_ERROR=""
	if node "$READABLE" --url "$url" --stats >"$tmp" 2>"$tmp.err"; then
		mv -f "$tmp" "$file"
		rm -f "$tmp.err"
		return 0
	fi
	EXTRACT_ERROR=$(head -1 "$tmp.err" 2>/dev/null || true)
	rm -f "$tmp" "$tmp.err"
	return 1
}

# Why the last extract_to_cache failed, in the engine's own words.
#
# The three causes used to be printed as one guess, which is worse than
# useless: LinkedIn answers with HTTP 999, a refusal to serve anything without
# a session, and reading that as the JavaScript limit sends you looking for a
# renderer that would not have helped.
extract_failure_reason() {
	local reason=${EXTRACT_ERROR#\[}
	reason=${reason%\]}
	case $reason in
	'' | *ENOENT*) reason="fetch failed" ;;
	'no article found' | 'no readable text extracted')
		reason="$reason, the page most likely builds its body in JavaScript"
		;;
	esac
	printf '%s' "$reason"
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
	# Say these are the result keys. Listed bare they read as available on this
	# screen, and ctrl-s in particular invites a press here, where read -e owns
	# the line and there is not yet a result set to refine.
	hint='in the results:  tab mark  enter open  ctrl-o read  ctrl-e nvim  ctrl-s refine'
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

# Print an extract as rendered markdown.
#
# The file itself holds no escape codes, so that it opens clean in an editor;
# colour is added here, at the point of printing. glow renders the document,
# with headings styled and prose wrapped to the pane. bat only highlights the
# source, so every "##" and "](" stays on screen, which is why it is the
# fallback rather than the choice. Both see a pipe rather than the preview
# pane, so the width has to be handed to them or they assume 80 columns.
render_markdown() {
	local file=$1 width=$2
	if command -v glow >/dev/null 2>&1; then
		glow --width="$width" "$file"
	elif command -v bat >/dev/null 2>&1; then
		bat --style=plain --color=always --paging=never \
			--language=markdown --terminal-width="$width" "$file"
	else
		sed $'s/^\\[kept .* characters of page text\\]$/\033[90m&\033[0m/' "$file"
	fi
}

# ---------------------------------------------------------------------------
# Query building. Operators do most of the work in a search and almost nobody
# types them, because the syntax has to be recalled at the moment you are
# thinking about the question. These build it instead.
# ---------------------------------------------------------------------------

# The value an operator already carries, so editing it starts from what the
# query says rather than from an empty line.
query_get() {
	local tokens=() t
	read -ra tokens <<<"$1"
	for t in "${tokens[@]}"; do
		if [[ $t == "$2"* ]]; then
			printf '%s' "${t#"$2"}"
			return 0
		fi
	done
	return 0
}

# Replace an operator's value rather than adding a second one. Two site: terms
# in one query match nothing, so refining twice has to overwrite the first.
# An empty value drops the operator, which is how a constraint is taken back.
query_set() {
	local query=$1 prefix=$2 value=$3 tokens=() out=() t
	read -ra tokens <<<"$query"
	for t in "${tokens[@]}"; do
		[[ $t == "$prefix"* ]] && continue
		out+=("$t")
	done
	[[ -n $value ]] && out+=("$prefix$value")
	printf '%s' "${out[*]}"
}

# Strip every operator and keep the words. Quoted phrases go first, as a whole
# run, because splitting on spaces would leave two thirds of one behind.
query_reset() {
	local bare tokens=() out=() t
	bare=$(printf '%s' "$1" | sed 's/"[^"]*"//g')
	read -ra tokens <<<"$bare"
	for t in "${tokens[@]}"; do
		case $t in
		*:*) continue ;;
		-?*) continue ;;
		esac
		out+=("$t")
	done
	printf '%s' "${out[*]}"
}

# The domains the current results came from, commonest first. These are the
# site: candidates worth offering: you learn what to constrain by seeing a bad
# result set, and the set names its own domains.
result_domains() {
	jq -r '.[].url' "$1" |
		awk -F/ 'NF > 2 { print $3 }' |
		sed 's/^www\.//' |
		sort | uniq -c | sort -k1,1nr -k2,2 | awk '{ print $2 }'
}

# The operators DuckDuckGo answers. Google's before:, after: and AROUND(n) are
# absent because DuckDuckGo ignores them, and bangs are absent because ddgr
# resolves a bang to a browser redirect and hands --json an empty set.
refine_menu() {
	printf '%-10s %s\n' \
		'site:' 'only this domain' \
		'-site:' 'everything except this domain' \
		'filetype:' 'only this kind of file' \
		'intitle:' 'the words must be in the title' \
		'inurl:' 'the words must be in the address' \
		'phrase' 'an exact wording, in quotes' \
		'exclude' 'drop results carrying a word' \
		'edit' 'edit the whole query by hand' \
		'reset' 'drop every operator, keep the words'
}

FILETYPES='pdf
md
txt
csv
json
yaml
xml
html
doc
docx
ppt
pptx
xls
xlsx'

# Pick a value from a list on stdin, or type one the list does not hold.
# Returns non-zero when the pick was abandoned, which leaves the query alone.
choose_value() {
	local prompt=$1 out rc=0 lines=()
	out=$(fzf --print-query --layout=reverse --prompt="$prompt" \
		--header='enter takes the highlighted line, or type your own') || rc=$?
	# 130 is esc or ctrl-c. Anything else is a value, including the typed
	# query fzf prints when nothing in the list matched it.
	[[ $rc -eq 130 ]] && return 1
	mapfile -t lines <<<"$out"
	if [[ ${#lines[@]} -ge 2 && -n ${lines[1]} ]]; then
		printf '%s' "${lines[1]}"
	else
		printf '%s' "${lines[0]}"
	fi
}

# Read one value with readline editing, prefilled with what the query already
# says. The prompt and the framing go to stderr: stdout is the value.
read_value() {
	local prompt=$1 prefill=$2 value
	clear >&2 2>/dev/null || true
	printf '\033[90m%s\033[0m\n\n' 'enter accepts · ctrl-c leaves the query alone' >&2
	read -r -e -i "$prefill" -p "$prompt > " value || return 1
	printf '%s' "$value"
}

# Run the search again behind the picker.
#
# A refinement that finds nothing must leave the old set standing. An empty
# picker with the query already spent is a dead end, and the whole point of
# refining is to be able to try a different constraint against what you saw.
run_query() {
	local file=$1 num=$2 query=$3 tmp
	tmp="$file.new"
	clear >&2 2>/dev/null || true
	printf '\033[90m  searching for %s ...\033[0m\n' "$query" >&2

	if ! search_ddgr "$tmp" "$num" "$query"; then
		set_note "$file" "$SEARCH_ERROR, kept the previous results"
		rm -f "$tmp"
		return 0
	fi

	mv -f "$tmp" "$file"
	printf '%s\n' "$query" >"$(query_file "$file")"
	# Warm the new set detached: this process ends the moment the picker
	# reloads, and a job of its own would go with it.
	(batch_extract "$file" &)
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
		render_markdown "$cached" "$width"
		printf '\n'
	else
		printf '\033[31m(no page text: %s)\033[0m\n' "$(extract_failure_reason)"
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
		printf '(no page text: %s)\n' "$(extract_failure_reason)"
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
	# Same renderer as the preview pane, so ctrl-o and the preview do not
	# disagree about what the same page looks like.
	if command -v glow >/dev/null 2>&1; then
		glow --pager "$combined"
	elif command -v bat >/dev/null 2>&1; then
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
	set_note "$file" 'bookmarked to pet-links.toml'
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

# The picker's rows: the result index, then a numbered title with its domain.
# A mode of its own because a refinement re-runs it through fzf's reload.
mode_list() {
	jq -r 'to_entries[] | "\(.key)\t\(.value.title)\t\(.value.url)"' "$1" |
		awk -F'\t' '{
			split($3, parts, "/")
			printf "%s\t%2d. %s  \033[90m[%s]\033[0m\n", $1, $1 + 1, $2, parts[3]
		}'
}

# The header: the query on top, the keys under it. The query is there because
# after two refinements the constraints in force are no longer something you
# can be expected to hold in your head. A note from the last action rides along
# on the same line and is cleared once shown, so it reads as what just
# happened rather than as part of the query.
mode_header() {
	local file=$1 note nf
	nf=$(note_file "$file")
	printf 'query: %s' "$(current_query "$file")"
	if [[ -s $nf ]]; then
		note=$(head -n1 "$nf")
		rm -f "$nf"
		printf '   (%s)' "$note"
	fi
	printf '\n%s\n' "$PICKER_KEYS"
}

# Build an operator onto the current query and search again.
#
# The builder lives here, over a result set, rather than in the search box:
# you learn what to constrain by seeing what came back, not before it. Every
# path out of the menu can be abandoned, and abandoning changes nothing.
mode_refine() {
	local file=$1 num=$2 query choice value new
	query=$(current_query "$file")

	choice=$(refine_menu | fzf --layout=reverse --prompt='refine > ' \
		--header="query: $query") || return 0
	choice=${choice%% *}

	case $choice in
	'site:' | '-site:')
		value=$(result_domains "$file" | choose_value "$choice ") || return 0
		new=$(query_set "$query" "$choice" "$value")
		;;
	'filetype:')
		value=$(printf '%s\n' "$FILETYPES" | choose_value 'filetype: ') || return 0
		new=$(query_set "$query" 'filetype:' "$value")
		;;
	'intitle:' | 'inurl:')
		value=$(read_value "$choice" "$(query_get "$query" "$choice")") || return 0
		new=$(query_set "$query" "$choice" "$value")
		;;
	'phrase')
		value=$(read_value 'exact phrase' '') || return 0
		[[ -z ${value//[[:space:]]/} ]] && return 0
		new="$query \"$value\""
		;;
	'exclude')
		value=$(read_value 'drop results with' '') || return 0
		[[ -z ${value//[[:space:]]/} ]] && return 0
		new="$query -$value"
		;;
	'edit')
		new=$(read_value 'query' "$query") || return 0
		;;
	'reset')
		new=$(query_reset "$query")
		;;
	*) return 0 ;;
	esac

	if [[ -z ${new//[[:space:]]/} ]]; then
		set_note "$file" "that would leave nothing to search for"
		return 0
	fi
	[[ $new == "$query" ]] && return 0
	run_query "$file" "$num" "$new"
}

# ---------------------------------------------------------------------------
# Main modes.
# ---------------------------------------------------------------------------

# One node process for the whole result set: eight separate runs would pay the
# jsdom import eight times over.
batch_extract() {
	node "$READABLE" --batch "$1" --cache "$CACHE_DIR" --stats >/dev/null 2>&1
}

# Warm the cache for every result at once, so previews are instant instead of
# blocking on a fetch each time the selection moves.
prefetch() {
	local file=$1 url
	if [[ $FORCE_REFETCH -eq 1 ]]; then
		while IFS= read -r url; do
			[[ -n $url ]] && rm -f "$(cache_file "$url")"
		done < <(jq -r '.[].url' "$file")
	fi
	batch_extract "$file" &
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
	local file=$1 num=$2 selected line idx url

	prefetch "$file"

	# Flow control would swallow ctrl-s before fzf ever saw it, and the M-g
	# popup runs on a fresh pty where XON/XOFF is on by default. Restored in
	# cleanup, so a terminal that wants ctrl-s to freeze keeps it.
	if [[ -e /dev/tty ]]; then
		TTY_STATE=$(stty -g </dev/tty 2>/dev/null || true)
		[[ -n $TTY_STATE ]] && { stty -ixon </dev/tty 2>/dev/null || true; }
	fi

	selected=$(
		mode_list "$file" |
			fzf --ansi --multi \
				--delimiter=$'\t' --with-nth=2.. \
				--prompt='result > ' \
				--header="$(mode_header "$file")" \
				--preview="$SELF --preview '$file' {1}" \
				--preview-window='right,58%,wrap,border-left' \
				--bind="ctrl-o:execute($SELF --read '$file' {+1})" \
				--bind="ctrl-e:execute($SELF --edit '$file' {+1})" \
				--bind="ctrl-a:execute-silent($SELF --bookmark '$file' {+1})+transform-header($SELF --header '$file')" \
				--bind="ctrl-y:execute-silent($SELF --copy '$file' {+1})" \
				--bind="ctrl-r:execute-silent($SELF --refetch '$file' {+1})+refresh-preview" \
				--bind="ctrl-s:execute($SELF --refine '$file' $num)+reload($SELF --list '$file')+transform-header($SELF --header '$file')" \
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
	local num="${DDGX_NUM:-8}" dump=0 failed=0 args=()
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
	--list)
		mode_list "$2"
		return 0
		;;
	--header)
		mode_header "$2"
		return 0
		;;
	--refine)
		shift
		mode_refine "$@"
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
		POPUP_MODE=1
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
	# Wipe that line whichever way the search went: a reason printed over a
	# half-erased "searching for ..." is how "HTTP Error 202: Acceptedes
	# finalizers ..." reaches the screen.
	failed=0
	search_ddgr "$RESULTS_FILE" "$num" "${args[*]}" || failed=1
	if [[ -t 1 ]]; then
		printf '\033[2K\r' >&2
	fi
	if [[ $failed -eq 1 ]]; then
		die "$SEARCH_ERROR"
	fi
	# What the picker refines from. Whatever shape the query arrived in, an
	# inline "s foo bar" or a line typed into the popup, it becomes one string
	# from here on.
	printf '%s\n' "${args[*]}" >"$(query_file "$RESULTS_FILE")"

	if [[ $dump -eq 1 ]] || [[ ! -t 1 ]]; then
		# Piped without -d: dump rather than start fzf on a headless stdout.
		mode_dump "$RESULTS_FILE"
	else
		mode_pick "$RESULTS_FILE" "$num"
	fi
}

main "$@"
