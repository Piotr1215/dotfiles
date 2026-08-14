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
#   __ddgx.sh '? why do pods stay terminating'   # ask, answer plus its sources
#   __ddgx.sh '?? why do pods stay terminating'  # ask harder, 15 steps
#   __ddgx.sh -a etcd defragmentation            # the same, without the prefix
#   __ddgx.sh --preset xhigh 'trace this claim'  # 100 steps, minutes
#
# Two engines, one picker. A question mark in front of the query asks the
# Perplexity Agent API instead of searching DuckDuckGo: the answer arrives as
# the first row, its sources fill the rest of the list, and every key that
# works on a search result works on them. The sources come back carrying
# title, url and snippet, which is exactly what a ddgr result carries, so
# nothing downstream has to know which engine produced the set.
#
# One mark or two. ? is the low preset, five retrieval steps, the answer you
# want before you have finished typing the question. ?? is high, fifteen steps,
# for the question you are actually sitting with. The row says which one ran,
# so an answer that reads thin names the cheaper preset that produced it and
# the fix is one more keystroke next time.
#
# The answer being a row rather than a screen of its own is what makes the two
# modes one tool. It previews like a result, ctrl-e keeps it as a note, and
# alt-h hands it to the pane below, so an answer can be read, kept and passed
# on by the keys already in your hands. The rows carry the numbers the answer
# cited them by, so a claim and the page behind it are found by the same
# number. The answer text itself is never rewritten, so the exact token form is
# whatever the model wrote ([1] or [web:1]); the number is the part that has to
# agree, and it does.
#
# A typed prefix rather than a key, because the search screen cannot have keys:
# read -e owns that line, and a shortcut advertised there does nothing, which
# is how ctrl-s came to look broken. ? is free of DuckDuckGo's operators, so
# nothing that used to be a search stops being one.
#
# From a result set, alt-q offers ask, web, and over an answer, follow. That
# menu is where a query is already rebuilt after seeing what came back, and
# switching engine is the same move as adding an operator: you learned
# something from the results. It costs no key and no header line, which the key
# audit below says is the price worth refusing to pay.
#
# The conversation is enter on the answer row. An answer that ends "I can narrow
# this to X or Y" is inviting a second turn, and without one the offer is a dead
# end you can only answer by starting over and typing the context back in by
# hand. The thread id comes back with every answer and goes out with the next
# question, so a follow-up can say "it" and mean what the last answer was about.
#
# enter, because that is the row the cursor is already on when you finish
# reading, and because on the answer row enter did nothing before: the row has
# no page to open. The menu entry stays for the times you have forgotten. Every
# turn reloads the list, which puts the cursor back on the answer, so the whole
# of a conversation is enter, type, read, enter, type, read.
#
# The transcript is the answer row, newest turn on top. Each turn carries the
# question, the answer, and that turn's own numbered sources, because the rows
# under it only ever show the newest turn's: a [1] three turns up is not
# today's [1], and the transcript has to be readable without them.
#
# Keys in the picker. tab marks results, and ctrl-e, ctrl-a, ctrl-y and ctrl-r
# apply to the whole marked set, so mark five and hit one key:
#   tab      mark / unmark          enter   open in the browser
#   ctrl-o   do the obvious thing with whatever the preview is showing:
#            a video or playlist opens in the player, a page whose text could
#            not be extracted is rendered in a headless browser and shown, and
#            anything else opens the marked extracts in a pager
#   ctrl-e   open extracts in nvim as markdown notes (kept, re-openable)
#   ctrl-a   bookmark into pet-links.toml, the file plink writes
#   alt-h    hand the extracts to the pane you opened the popup from
#   ctrl-y   copy the URLs          ctrl-r  re-fetch (bypass cache)
#   alt-q    refine the query       ctrl-v  toggle the preview pane
#   ctrl-d/u scroll the preview
#
# alt-h is for the agent in the pane underneath. It pastes the note PATHS, not
# the note text, and it does not press Enter: you type what you want done with
# them. A delivered hand-off closes the popup, because the next thing to happen
# is you typing into the pane it just wrote to, and the search is in the way of
# that. A hand-off that failed leaves the picker up to say so. An agent asked to fetch a page for itself cannot tell you whether it
# was throttled, redirected or handed a stub, and WebFetch-style tools return
# someone else's summary rather than the page. This hands over exactly the
# markdown you just read, which you chose, from a cache you can inspect.
#
# One key rather than three. Play, render and read were ctrl-v, ctrl-x and
# ctrl-o, three keys you had to hold in your head along with which one the row
# under the cursor would accept. But the preview pane has already worked out
# what the result is by the time you reach for a key: it is showing a video, or
# it is showing the red line that says the text could not be extracted, or it
# is showing the text. So the key asks the preview rather than asking you.
#
# alt-q builds the query instead of asking you to recall the syntax. Pick an
# operator, fill in its value, and the search re-runs under the picker. site:
# offers the domains the current results came from, filetype: offers a list,
# and an operator already in the query arrives prefilled so narrowing it is an
# edit. The raw query stays editable from the same menu, and a refinement that
# finds nothing leaves the previous results standing.
#
# Env: DDGX_TTL (cache seconds, default 86400), DDGX_JOBS (prefetch
# concurrency, default 6), DDGX_NUM (default result count), DDGX_EDITOR
# (ctrl-e editor, default nvim), DDGX_PET_FILE (bookmark file), DDGX_PLAYER
# (the player ctrl-o opens a video in, default mpv), DDGX_PLAYER_ARGS (extra
# player arguments), DDGX_PPLX_PRESET (ask depth, default low), DDGX_ASK_CMD
# (the ask backend, default __search_internet.py).
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
READABLE="$SCRIPT_DIR/__readable.mjs"
# Shared with __orchestrator.sh: both are popups that hand text back to the pane
# they were opened from.
source "$SCRIPT_DIR/__lib_pane_deliver.sh"
MODULES_DIR="${DDGX_MODULES:-$HOME/.local/share/ddgx}"
# The MarkDownload settings export, stowed from .config/ddgx in this repo.
OPTIONS_FILE="${DDGX_OPTIONS:-${XDG_CONFIG_HOME:-$HOME/.config}/ddgx/markdownload-options.json}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/ddgx"
# Notes are durable: they live outside the cache so clearing extracts, or a
# stale-cache sweep, can never take hand-edited notes with them.
NOTES_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/ddgx/notes"
CACHE_TTL="${DDGX_TTL:-86400}"
FORCE_REFETCH=0
# The ask backend owns the Agent API protocol (background run, then polling)
# so this script never speaks it. Overridable because a path resolved from
# SCRIPT_DIR cannot be stubbed on PATH, and the suite has to stub it.
ASK_CMD="${DDGX_ASK_CMD:-$SCRIPT_DIR/__search_internet.py}"
# Two depths, because a question you ask in passing and a question you sit with
# are not the same question. low is 5 retrieval steps, enough for a real answer
# and cheap enough to type without thinking about it. high is 15 and reads like
# what Deep Research used to cost a plan.
#
# xhigh and wide-research are 100 steps and minutes of waiting. They are not
# behind a prefix on purpose: a popup you opened to answer something in passing
# is the wrong place to start a run that long. --preset reaches them when the
# spend is the point.
PPLX_PRESET="${DDGX_PPLX_PRESET:-low}"
PPLX_DEEP_PRESET="${DDGX_DEEP_PRESET:-high}"
PET_LINKS="${DDGX_PET_FILE:-$HOME/dev/pet-snippets/pet-links.toml}"
# alt-q for the refiner, because every ctrl letter is already spoken for and an
# existing binding wins. ctrl-s is XOFF: on the fresh pty the M-g popup runs
# on, the tty stops the screen and swallows everything until ctrl-q, and where
# flow control is already off readline takes it for i-search. ctrl-t is
# readline's transpose-chars. Cross-checking readline, tmux's root table, fzf's
# defaults and the keys above leaves alt-h, alt-j, alt-q and alt-v; alt-q is
# the one that stands for something.
#
# There was an audit here for the three keys play, render and yt-x used to
# hold. It is gone with them. A key spend is a budget nobody was asking to
# spend: the whole of that audit bought three keys that each did one thing to
# some rows and nothing to the others, and the fix was not a better key but
# one fewer. What is left fits inside fzf's and readline's defaults without
# argument.
#
# ctrl-v toggles the preview, taking over from ctrl-\, which never worked and
# could not. .tmux.conf binds C-\ in the ROOT table, which answers before the
# pane's program is offered the key at all, so tmux switched panes and fzf
# received nothing. Every ddgx session runs inside tmux through the M-g popup,
# so the key was dead in practice for as long as the header advertised it.
#
# How that was established matters, because the obvious probe gives the wrong
# answer. `tmux send-keys` injects into the pane and BYPASSES the root table,
# so a send-keys test shows only that fzf handles a key, never that the key
# would reach fzf in use. The evidence is .tmux.conf's own root bindings, which
# claim C-h, C-j, C-k, C-l and C-\ and nothing else in the ctrl space. Read the
# config, do not probe. ctrl-v is clear there, clear of fzf's ctrl defaults
# (a b c d e f g h i j k l n p q u w y), and free at all because collapsing
# play, render and yt-x into ctrl-o gave three keys back.
#
# Two lines, because one is longer than the pane. fzf gives the header the
# width of the result list, not of the terminal, so at the default 58% preview
# a single line is cut around 98 columns and everything after it is simply
# gone. A key you cannot see does not exist, so both lines have to stay short
# enough to survive that cut. The suite measures them.
PICKER_KEYS='tab mark · enter open · ctrl-o play, render or read · ctrl-e nvim · ctrl-v preview
ctrl-a bookmark · ctrl-y copy · ctrl-r refetch · alt-q refine · alt-h hand to pane'

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

# Ask the Agent API and shape the reply into the same result set a search
# produces: the answer as row 0, then every source it cited.
#
# The sources are NOT trimmed to -n, unlike a web search. The answer cites them
# by number, so a list cut at 8 would leave a claim marked [9] pointing at a row
# that is not on screen. The count belongs to the engine that produced the
# answer, not to a display preference.
#
# Same contract as search_ddgr: writes the result set, sets SEARCH_ERROR, and
# returns non-zero when nothing usable came back.
search_pplx() {
	local out=$1 query=$2 answer=$3 thread=$4 continue_id=${5:-}
	local raw err rc=0 text turn title args=() turnfile
	raw=$(mktemp -t ddgx-ask-XXXXXX.json)
	err=$(mktemp -t ddgx-err-XXXXXX)
	SEARCH_ERROR=''

	args=(--json --preset "$PPLX_PRESET")
	# The thread is what makes a follow-up able to say "it". Without the id the
	# next question arrives with no idea what the last answer was about, which
	# is the difference between a conversation and two unrelated searches.
	[[ -n $continue_id ]] && args+=(--continue "$continue_id")

	"$ASK_CMD" "${args[@]}" "$query" >"$raw" 2>"$err" || rc=$?
	text=$(jq -r '.answer // ""' "$raw" 2>/dev/null || printf '')

	# An answer with no sources is still an answer, so the test is whether the
	# model said anything, not whether it cited anything.
	if [[ $rc -ne 0 || -z ${text//[[:space:]]/} ]]; then
		SEARCH_ERROR=$(head -1 "$err" 2>/dev/null || true)
		[[ -z $SEARCH_ERROR ]] && SEARCH_ERROR='the answer came back empty'
		rm -f "$raw" "$err"
		return 1
	fi

	turn=$(sed -n '2p' "$thread" 2>/dev/null || true)
	[[ -z $turn ]] && turn=0
	turn=$((turn + 1))
	# A fresh ask starts the count again: it is a new conversation, whatever the
	# last one was about.
	[[ -n $continue_id ]] || turn=1
	title="answer · perplexity $PPLX_PRESET"
	[[ $turn -gt 1 ]] && title="$title · turn $turn"

	jq --arg title "$title" '
		[{title: $title, url: "", abstract: "", ref: ""}]
		+ [ .results[] | {
			title: (.title // .url),
			url: .url,
			abstract: ((.snippet // "")
				| if length > 300 then .[0:300] + " ..." else . end),
			ref: (if .id == null then "" else (.id | tostring) end)
		} ]' "$raw" >"$out"

	# One turn of the transcript: the question, the answer, and the sources
	# that answer cited, numbered as it numbered them. Each turn carries its
	# own references because the rows only ever show the newest turn's sources,
	# and a [1] three turns up points at a different page than today's [1].
	turnfile=$(mktemp -t ddgx-turn-XXXXXX.md)
	{
		printf '## %s\n\n' "$query"
		printf '%s\n' "$text"
		jq -r 'if (.results | length) > 0 then
				"", ([.results[]] | to_entries[]
					| "[\(.value.id // (.key + 1))]: \(.value.url)")
			else empty end' "$raw"
	} >"$turnfile"

	# Newest turn on top. The preview pane opens at the top of the file, and in
	# a conversation the thing you just asked for is the thing you want to
	# read; a chronological transcript would put it below a screen of history
	# and make every follow-up start with a scroll.
	if [[ -n $continue_id && -s $answer ]]; then
		{
			cat "$turnfile"
			printf '\n---\n\n'
			cat "$answer"
		} >"$answer.new"
		mv -f "$answer.new" "$answer"
	else
		mv -f "$turnfile" "$answer"
	fi

	{
		jq -r '.id // ""' "$raw"
		printf '%s\n' "$turn"
		printf '%s\n' "$PPLX_PRESET"
	} >"$thread"

	rm -f "$raw" "$err" "$turnfile"
	return 0
}

# Which engine produced the current set. Absent means a web search, so a set
# written before this file knew about engines still refines correctly.
current_engine() {
	local ef
	ef=$(engine_file "$1")
	if [[ -s $ef ]]; then
		head -n1 "$ef"
	else
		printf 'ddgr'
	fi
	return 0
}

set_engine() { printf '%s\n' "$2" >"$(engine_file "$1")"; }

# Preserve the script's real exit status: a kill of an already-reaped prefetch
# would otherwise become the status the caller sees.
cleanup() {
	local status=$?
	if [[ -n ${RESULTS_FILE:-} ]]; then
		rm -f "$RESULTS_FILE" "$(query_file "$RESULTS_FILE")" \
			"$(note_file "$RESULTS_FILE")" "$(target_file "$RESULTS_FILE")" \
			"$(answer_file "$RESULTS_FILE")" "$(engine_file "$RESULTS_FILE")" \
			"$(thread_file "$RESULTS_FILE")" "$RESULTS_FILE.new"
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
# The answer text for an ask set, and which engine produced the set. The engine
# has to be recorded rather than inferred: a refinement re-runs the search, and
# a set that came from an answer must refine into another answer rather than
# silently turning into a web search.
answer_file() { printf '%s.answer' "$1"; }
engine_file() { printf '%s.engine' "$1"; }
# The conversation: the run id a follow-up continues from on line one, how many
# turns have been asked on line two, and the preset it is being held at on line
# three. The count is kept rather than counted back out of the transcript,
# because an answer is free to write its own "##" headings and a grep for them
# would report the model's structure as turns.
#
# The preset is kept because a conversation started with ?? is a deep
# conversation, and a follow-up that quietly dropped to the cheap default would
# answer the hardest question in the thread with the least effort.
thread_file() { printf '%s.thread' "$1"; }

thread_id() {
	local tf
	tf=$(thread_file "$1")
	[[ -s $tf ]] && sed -n '1p' "$tf"
	return 0
}

thread_turns() {
	local tf n
	tf=$(thread_file "$1")
	n=$(sed -n '2p' "$tf" 2>/dev/null || true)
	printf '%s' "${n:-0}"
}

thread_preset() {
	local tf
	tf=$(thread_file "$1")
	sed -n '3p' "$tf" 2>/dev/null || true
	return 0
}
# The pane alt-h hands extracts back to, resolved once when the search starts
# and pinned here for the life of it. Reading the global tmux option at send
# time instead would hand this search's extracts to whatever pane opened a
# popup most recently, which is not necessarily the one you pressed M-g in.
target_file() { printf '%s.target' "$1"; }

current_query() {
	local qf
	qf=$(query_file "$1")
	[[ -s $qf ]] && head -n1 "$qf"
	return 0
}

set_note() { printf '%s\n' "$2" >"$(note_file "$1")"; }

# Everything cached about one URL shares a name: the sha1 of the URL, with the
# extension saying which of the three files it is. The extractor computes the
# same key from the same URL, which is what lets the two sides find each
# other's writes without passing paths around.
cache_key() {
	printf '%s' "$1" | sha1sum | cut -d' ' -f1
}

# Path of the extract cache entry for a URL.
cache_file() { printf '%s/%s.txt' "$CACHE_DIR" "$(cache_key "$1")"; }

# The sidecar the extractor writes beside an entry when the URL turned out to
# hold a video or a playlist rather than a page: kind, title, thumbnail,
# webpage_url and duration, as JSON. It exists if and only if there is
# something to play, so its presence is the answer to "is this playable" and
# this script never re-derives that answer from the URL when it is there.
#
# The reason for taking the extractor's word is that the extractor asked
# yt-dlp, and yt-dlp is what will have to play the thing. A URL that looks like
# a video and that yt-dlp cannot resolve is not playable however much it looks
# the part, and no amount of pattern matching over a URL finds that out.
media_file() { printf '%s/%s.media' "$CACHE_DIR" "$(cache_key "$1")"; }

# The still frame, downloaded once and kept. The preview command runs again on
# every keystroke that moves the selection, so a thumbnail fetched per keypress
# would make the pane slower than the page extract drawn under it.
thumb_file() { printf '%s/%s.jpg' "$CACHE_DIR" "$(cache_key "$1")"; }

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
	# --cache is here for the sidecar, not for the text: it is what makes the
	# extractor record that this URL held a video, and that record is the only
	# thing telling the picker a result is playable. The text still arrives on
	# stdout, and an empty stdout is never allowed to overwrite the entry, so an
	# extractor that writes the file itself and one that only prints it both
	# come out the same.
	local rc=0
	node "$READABLE" --url "$url" --cache "$CACHE_DIR" --stats \
		>"$tmp" 2>"$tmp.err" || rc=$?
	if [[ $rc -eq 0 ]]; then
		[[ -s $tmp ]] && mv -f "$tmp" "$file"
		rm -f "$tmp" "$tmp.err"
		if [[ -s $file ]]; then
			return 0
		fi
		EXTRACT_ERROR='the extractor returned no text'
		return 1
	fi
	EXTRACT_ERROR=$(head -1 "$tmp.err" 2>/dev/null || true)
	rm -f "$tmp" "$tmp.err"
	return 1
}

# Escalate one URL to the deep extractor and overwrite whatever the cheap path
# left in the cache. The engine renders the page in headless Chrome and falls
# back to a w3m text dump of the DOM that came out, which costs 5 to 25 seconds
# and is why nothing calls this on its own.
#
# Deliberately not TTL-aware, unlike extract_to_cache: you ask for this because
# what is on screen is wrong, and a fresh-but-useless entry is precisely the
# thing to replace. A failed render leaves the old entry standing, because a
# thin extract still beats an empty pane.
deep_extract() {
	local url=$1 file tmp
	file=$(cache_file "$url")
	mkdir -p "$CACHE_DIR"
	tmp="$file.$$"
	EXTRACT_ERROR=""
	if node "$READABLE" --deep --url "$url" --stats >"$tmp" 2>"$tmp.err"; then
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
	# screen, where read -e owns the line and there is not yet a result set to
	# refine.
	#
	# A selection, not the whole list, and its length is load-bearing: this is
	# centred on one line, and a hint that wraps pushes the cursor arithmetic
	# below it off by a row and draws the input box in the wrong place. The keys
	# left off it are in the picker's own header, where they apply. None of
	# these work on this screen either, which is why the line says where they do.
	hint='in the results:  tab mark  enter open  ctrl-o play, render or read  alt-q refine'
	clear 2>/dev/null || true

	# Both lines are centred and neither may wrap, for the same reason the hint
	# may not: the cursor arithmetic below counts rows, and a wrapped line moves
	# the input box off the row this draws it on.

	local width fill
	width=$((cols - 8))
	[[ $width -gt 70 ]] && width=70
	[[ $width -lt 24 ]] && width=24
	indent=$(((cols - width) / 2))
	[[ $indent -lt 0 ]] && indent=0
	fill=$(printf '%*s' "$((width - 2))" '')
	fill=${fill// /─}

	pad=$(((rows - 8) / 2))
	for ((i = 0; i < pad; i++)); do printf '\n'; done

	center "$cols" 'duckduckgo results with the page text extracted' '\033[90m'
	center "$cols" 'start with ? to ask perplexity, ?? to ask harder' '\033[90m'
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
	# follow only exists where there is something to follow, and it goes first
	# because a conversation is a sequence of them: alt-q, enter, type. An entry
	# offered over a web result set would be a dead option on every search.
	if [[ $(current_engine "${1:-}") == pplx ]]; then
		printf '%-10s %s\n' 'follow' 'ask a follow-up in the same conversation'
	fi
	printf '%-10s %s\n' \
		'ask' 'ask perplexity this, answer with its sources' \
		'web' 'search duckduckgo for this instead' \
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
	local file=$1 num=$2 query=$3 engine=${4:-} follow=${5:-0}
	local tmp ok=0 continue_id='' held=''
	tmp="$file.new"
	[[ -z $engine ]] && engine=$(current_engine "$file")
	clear >&2 2>/dev/null || true

	if [[ $engine == pplx ]]; then
		if [[ $follow -eq 1 ]]; then
			continue_id=$(thread_id "$file")
			# A conversation is held at the depth it was started at. Dropping to
			# the cheap default here would answer the follow-up, usually the
			# harder question, with less effort than the one that opened it.
			held=$(thread_preset "$file")
			[[ -n $held ]] && PPLX_PRESET=$held
		fi
		if [[ -n $continue_id ]]; then
			printf '\033[90m  following up (%s) ...\033[0m\n' "$PPLX_PRESET" >&2
		else
			printf '\033[90m  asking perplexity (%s) about %s ...\033[0m\n' \
				"$PPLX_PRESET" "$query" >&2
		fi
		search_pplx "$tmp" "$query" "$(answer_file "$file")" \
			"$(thread_file "$file")" "$continue_id" || ok=1
	else
		printf '\033[90m  searching for %s ...\033[0m\n' "$query" >&2
		search_ddgr "$tmp" "$num" "$query" || ok=1
		# Leaving the old answer behind would keep a previous ask's text on disk
		# under a set that no longer has a row to show it, and its thread id
		# would let a later follow-up continue a conversation the picker has no
		# trace of.
		[[ $ok -eq 0 ]] && rm -f "$(answer_file "$file")" "$(thread_file "$file")"
	fi

	if [[ $ok -ne 0 ]]; then
		set_note "$file" "$SEARCH_ERROR, kept the previous results"
		rm -f "$tmp"
		return 0
	fi

	set_engine "$file" "$engine"
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
	local file=$1 idx=$2 width url title abstract cached still af
	width=$((${FZF_PREVIEW_COLUMNS:-100} - 2))
	[[ $width -lt 40 ]] && width=40

	url=$(result_field "$idx" "$file" url)
	title=$(result_field "$idx" "$file" title)
	abstract=$(result_field "$idx" "$file" abstract)

	# The answer row. No url, so nothing to fetch and nothing to extract: the
	# text is already here, rendered by the same renderer the extracts use so
	# the two do not disagree about what markdown looks like.
	if [[ -z $url ]]; then
		af=$(answer_file "$file")
		printf '\033[1;35m%s\033[0m\n' "$title"
		# The pane names the key, the way it does for a video. A conversation
		# nobody knows how to continue is a feature that reads as a dead end.
		printf '\033[90m(enter asks a follow-up)\033[0m\n\n'
		if [[ -s $af ]]; then
			render_markdown "$af" "$width"
		else
			printf '\033[31m(the answer is gone)\033[0m\n'
		fi
		return 0
	fi

	printf '\033[1;36m%s\033[0m\n' "$title"
	printf '\033[33m%s\033[0m\n\n' "$url"

	if is_playable "$url"; then
		# The still frame goes above the metadata and the transcript, so the
		# pane opens with the one thing that says what this video is faster
		# than any line of text under it can.
		#
		# Sized to a share of the pane rather than to the pane, because the
		# text below it is the reason the result is in a search tool at all.
		still=$((${FZF_PREVIEW_LINES:-30} * 2 / 5))
		[[ $still -lt 8 ]] && still=8
		[[ $still -gt 20 ]] && still=20
		if show_still "$url" "$width" "$still"; then
			printf '\n'
		fi
		printf '\033[90m(ctrl-o opens it in the player)\033[0m\n\n'
	fi

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
		# Name the way out here rather than only in the help text. This line is
		# the one moment the escalation means anything, and a reason with no
		# next step is where the tool used to stop.
		printf '\033[31m(no page text: %s)\033[0m\n' "$(extract_failure_reason)"
		printf '\033[90m(ctrl-o loads it in a headless browser and reads that, a few seconds)\033[0m\n'
	fi
}

# Write "# title / Source: url / extract" for one result to stdout.
emit_note() {
	local file=$1 idx=$2 url title cached af
	url=$(result_field "$idx" "$file" url)
	title=$(result_field "$idx" "$file" title)

	# The answer keeps and travels like a page does. Its source line names the
	# engine and the question rather than a url, because that pair is what you
	# would have to know to get this text again.
	if [[ -z $url ]]; then
		af=$(answer_file "$file")
		printf '# %s\n\n' "$(current_query "$file")"
		printf 'Source: %s\n\n' "$title"
		if [[ -s $af ]]; then
			cat "$af"
			printf '\n'
		else
			printf '(the answer is gone)\n'
		fi
		return 0
	fi

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

# Materialise durable notes for the given result indices and print their paths,
# one per line.
#
# Shared by ctrl-e, which opens them, and alt-h, which hands the paths to
# another pane. One naming rule for both: a path you were given by alt-h has to
# be the same file ctrl-e would have opened, or the two keys quietly disagree
# about what "this result" means.
note_paths() {
	local file=$1 idx title slug note
	shift
	mkdir -p "$NOTES_DIR"
	for idx in "$@"; do
		# An index past the end of the results would otherwise leave an empty
		# note behind in a directory that is meant to be durable. Title rather
		# than url, because the answer row has a title and no url and is still a
		# note worth keeping.
		title=$(result_field "$idx" "$file" title)
		[[ -n $title ]] || continue
		# The answer's filename comes from the question. "answer-perplexity-low"
		# would name every answer the same thing, and these notes outlive the
		# search that produced them.
		[[ -n $(result_field "$idx" "$file" url) ]] || title=$(current_query "$file")
		# Flatten whitespace FIRST. A page title carrying a newline survives the
		# rest of this pipeline, because tr, sed and cut are all line-oriented,
		# and the result is a path printed across two lines. Every caller reads
		# these one-per-line, so that single result silently became two broken
		# paths: the editor opened neither and the hand-off shipped both.
		slug=$(printf '%s' "$title" | tr '\n\r\t' '   ' | tr '[:upper:]' '[:lower:]' |
			sed 's/[^a-z0-9]\+/-/g; s/^-//; s/-$//' | cut -c1-60)
		[[ -z $slug ]] && slug="result-$idx"
		note="$NOTES_DIR/$slug.md"
		scaffold_note "$file" "$idx" "$note"
		printf '%s\n' "$note"
	done
}

# Open the extracts as markdown notes, kept in a durable directory so anything
# worth editing survives the search that produced it.
mode_edit() {
	local file=$1 notes=() editor
	shift
	mapfile -t notes < <(note_paths "$file" "$@")
	# No valid indices means no files. Opening the editor on an empty argument
	# list drops you into a scratch buffer with no way back to the picker.
	[[ ${#notes[@]} -gt 0 ]] || return 0

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

# alt-h: hand the marked extracts to the pane M-g was pressed from.
#
# What travels is the note PATH, never the note text. The agent in that pane
# reads the file itself, at full fidelity, on its own schedule; a page it turns
# out not to need costs it nothing. Pasting the markdown instead would put
# kilobytes on an input line, which is slow, lossy at the edges, and impossible
# to review before it is sent.
#
# Nothing is submitted. The paths land on the input line and you type what you
# want done with them, which is also the safety property: a wrong send is a
# line you clear, not a turn you interrupted.
mode_send() {
	local file=$1 notes=() payload target label tf
	shift
	mapfile -t notes < <(note_paths "$file" "$@")
	if [[ ${#notes[@]} -eq 0 ]]; then
		set_note "$file" 'nothing to hand off'
		printf 'transform-header(%s --header %s)' "$SELF" "$file"
		return 0
	fi

	# Read the pinned target defensively. `$(<missing)` under `set -e` kills the
	# process before any `||` fallback runs, and the error escapes through
	# fzf's stderr onto the picker, which is the one outcome this mode exists
	# to avoid.
	tf=$(target_file "$file")
	target=""
	[[ -r $tf ]] && target=$(<"$tf")
	payload=$(printf '%s\n' "${notes[@]}")

	if deliver_to_pane "$target" "$payload"; then
		clear_popup_source_pane
		# The hand-off is the end of the search. The paths are on the input line
		# of the pane underneath and the next thing to happen is you typing what
		# to do with them, which the popup is sitting on top of. Nothing is
		# reported because there is no longer a header to report into: the
		# delivery is visible in the pane, which is a better receipt than a line
		# of text about it.
		printf 'abort'
	else
		# Say which of the two failures it was, and stay up to say it. "It did
		# nothing" is the report that costs an evening, and a popup that closed
		# on a failed hand-off is exactly that report.
		if [[ -z $target ]]; then
			set_note "$file" 'no source pane: alt-h works when ddgx runs from the M-g popup'
		else
			set_note "$file" "pane $target is gone, nothing handed off"
		fi
		printf 'transform-header(%s --header %s)' "$SELF" "$file"
	fi
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

# ctrl-o. One key, three things, chosen by what the preview pane is showing for
# the result under the cursor.
#
# The choice is made from the same state the pane drew itself from, which is
# what keeps the key honest: it cannot offer to play something the pane is not
# showing as a video, and it cannot offer to render a page whose text is
# already on screen.
#
# Nothing is done here except the render. This runs as fzf's transform action,
# whose contract is that the command prints fzf actions and fzf performs them,
# and that indirection is what lets one key reach three different fzf
# mechanisms from one place:
#
#   play    the player is launched detached, in its own window, and the header
#           is asked to say so. See play_detached for why the window and not
#           the preview pane.
#   render  the deep extractor is slow and silent, so it runs here, where fzf
#           is already holding the picker still, and the pane is refreshed
#           over the new cache entry afterwards.
#   read    the pager wants the whole terminal, which is what execute() hands
#           it. fzf restores the picker when it exits.
#
# The render never fires on its own when the cheap extract fails, and that is
# still true with it behind a shared key: the deep path costs 5 to 25 seconds
# a page, and a preview that blocked for that long while you arrowed down a
# result list would teach you to stop moving the cursor. Spending the time on a
# keypress is a choice, having it spent for you is not.
mode_action() {
	local file=$1 idx=$2 url
	shift 2
	url=$(result_field "$idx" "$file" url)

	if is_playable "$url"; then
		play_detached "$file" "$url"
		printf 'transform-header(%s --header %s)' "$SELF" "$file"
		return 0
	fi

	# No cache entry means the cheap extract could not read this page. The
	# preview ran it before you got here, and a failed extract is never cached,
	# so the absence of the file is the same fact the red line in the pane is
	# reporting. Testing it costs nothing, where re-running the extract to find
	# out would put a second fetch between the keypress and the render.
	if [[ -n $url && ! -s $(cache_file "$url") ]]; then
		# Set before the work as well as after. fzf holds the picker frozen for
		# the whole of this, so if it is cut short partway the header still says
		# what the key was doing rather than showing the last unrelated note.
		set_note "$file" 'rendering in a browser, this takes a moment'
		if deep_extract "$url"; then
			set_note "$file" 'rendered the slow way'
		else
			set_note "$file" "still unreadable: $(extract_failure_reason)"
		fi
		printf 'refresh-preview+transform-header(%s --header %s)' "$SELF" "$file"
		return 0
	fi

	# Everything else: the marked set, in a pager, exactly as ctrl-o always did.
	printf 'execute(%s --read %s %s)' "$SELF" "$file" "$*"
}

# Ask the next question in the conversation.
#
# A mode of its own because two keys reach it: enter on the answer row, which is
# the one you actually use, and follow in the alt-q menu, which is where you
# look when you have forgotten that enter does it.
mode_follow() {
	local file=$1 num=$2 followup
	if [[ $(current_engine "$file") != pplx ]]; then
		set_note "$file" 'nothing to follow: this set came from a web search'
		return 0
	fi
	# The question replaces the query outright rather than building on it: the
	# thread already holds what was asked before, so carrying the old words
	# forward would ask the same thing twice in one breath.
	followup=$(read_value 'follow up' '') || return 0
	[[ -z ${followup//[[:space:]]/} ]] && return 0
	run_query "$file" "$num" "$followup" pplx 1
}

# enter. On a page it opens the page, which is what enter has always done here.
# On the answer it asks the next question.
#
# That row is where the cursor already sits when you finish reading, and a
# conversation is a sequence of follow-ups: alt-q, enter, type was three
# keystrokes of ceremony around the one thing you came back to do. It costs no
# key, because enter on the answer row did nothing at all before: the row has no
# url, and mode_pick only ever opened rows that had one.
#
# Same transform contract as ctrl-o: this prints the actions and fzf performs
# them, which is what lets one key mean two things without either of them being
# a compromise.
mode_enter() {
	local file=$1 idx=$2 num=$3

	if [[ -n $(result_field "$idx" "$file" url) ]]; then
		printf 'accept'
		return 0
	fi

	printf 'execute(%s --follow %s %s)+reload(%s --list %s)+transform-header(%s --header %s)' \
		"$SELF" "$file" "$num" "$SELF" "$file" "$SELF" "$file"
}

mode_open() {
	local url=$1
	if [[ -n ${BROWSER:-} ]] && command -v "$BROWSER" >/dev/null 2>&1; then
		nohup "$BROWSER" "$url" >/dev/null 2>&1 &
	else
		nohup xdg-open "$url" >/dev/null 2>&1 &
	fi
}

# True when a URL names something a player can open rather than a page to read.
#
# Matched on hostname plus path, never on a substring of the whole URL. Search
# results are full of pages that carry "youtube.com/watch?v=..." inside their
# own query string, an aggregator or a redirect wrapper, and a substring test
# hands one of those to the player, which then plays the wrapper. Cutting the
# query and the fragment off first is what makes the host and the path mean
# what they say.
is_media_url() {
	local url=$1 rest host path query=''
	rest=${url#*://}
	rest=${rest%%\#*}
	# One exception to the rule above: a youtube playlist names what to play in
	# its query and nowhere else, so the query is kept for that case alone.
	[[ $rest == *\?* ]] && query=${rest#*\?}
	rest=${rest%%\?*}
	host=${rest%%/*}
	path=${rest#"$host"}
	host=${host%%:*}
	host=${host,,}
	host=${host#www.}

	case $host in
	youtube.com | m.youtube.com)
		# /feed, /results, /@channel and the bare front page are pages, not
		# something to hand a player: only the paths naming something to play.
		[[ $path == /watch || $path == /shorts/?* ]] && return 0
		# A playlist is playable too. yt-dlp resolves list= into its videos and
		# the player takes the whole run as a queue, which is the same thing
		# marking five results and hitting play already does.
		[[ $path == /playlist && $query == *list=* ]]
		;;
	youtu.be)
		# The whole host is the shortener, so any id at all is a video.
		[[ $path == /?* ]]
		;;
	vimeo.com | player.vimeo.com)
		# vimeo.com/76979871, and the channel and embed forms that end the same
		# way. /upgrade and /features end in a word, so they miss.
		[[ $path =~ ^(/[A-Za-z0-9_-]+)*/[0-9]+/?$ ]]
		;;
	twitch.tv | m.twitch.tv) [[ $path == /videos/?* || $path == /clips/?* ]] ;;
	dailymotion.com) [[ $path == /video/?* ]] ;;
	# Odysee names a video either under its channel or with a claim id after a
	# colon; /$/download and the rest of the site have neither.
	odysee.com) [[ $path == /@*/?* || $path == /*:* ]] ;;
	rumble.com) [[ $path == /v*.html || $path == /embed/?* ]] ;;
	*) return 1 ;;
	esac
}

# Read one field out of the media sidecar. Missing file, missing field and
# malformed JSON all come back empty, because a preview pane is the wrong place
# to learn that a cache file was truncated.
media_field() {
	local sidecar=$1 field=$2
	[[ -s $sidecar ]] || return 0
	jq -r --arg f "$field" '.[$f] // ""' "$sidecar" 2>/dev/null || true
}

# True when this result is something to play rather than a page to read.
#
# The sidecar answers first and its answer is final: the extractor got it from
# yt-dlp, which is the tool that would have to play the thing. is_media_url is
# the fallback for the case where the extractor has not answered at all, a
# prefetch that has not landed yet or an extract that never ran, and it is
# still worth having because a youtu.be link is a video whether or not anything
# has looked at it yet.
is_playable() {
	local url=$1
	[[ -z $url ]] && return 1
	if [[ -s $(media_file "$url") ]]; then
		return 0
	fi
	is_media_url "$url"
}

# Seconds the URL resolve may take before the pane says so and gives up. Long
# enough for yt-dlp to walk a playlist, short enough that a pane which is going
# to fail says so while you are still looking at it.
# Draw the still frame for a media result, the thumbnail the sidecar names.
#
# chafa's symbol output is plain text with colour, so it needs no image
# protocol from the terminal and no cooperation from fzf: it draws inside the
# preview border in alacritty exactly like the extract under it does.
show_still() {
	local url=$1 cols=$2 lines=$3 jpg thumb
	command -v chafa >/dev/null 2>&1 || return 1
	jpg=$(thumb_file "$url")
	if [[ ! -s $jpg ]]; then
		thumb=$(media_field "$(media_file "$url")" thumbnail)
		[[ -z $thumb ]] && return 1
		command -v curl >/dev/null 2>&1 || return 1
		mkdir -p "$CACHE_DIR"
		curl -fsSL --max-time 10 -o "$jpg.$$" "$thumb" >/dev/null 2>&1 ||
			{
				rm -f "$jpg.$$"
				return 1
			}
		[[ -s $jpg.$$ ]] || {
			rm -f "$jpg.$$"
			return 1
		}
		mv -f "$jpg.$$" "$jpg"
	fi
	chafa --format symbols --size "${cols}x${lines}" "$jpg" 2>/dev/null
}

# Open a result in the player, in its own window, detached the way mode_open
# detaches: the picker stays up and the player must neither own its terminal
# nor die with the keypress that started it.
#
# The video does not play in the preview pane, and that was tried rather than
# assumed. mpv's tct output does draw inside the preview border, but a 58
# column pane is about 58 by 40 effective pixels, and at that size a video is
# something you can identify and not something you can watch. Alacritty has
# neither sixel nor the kitty graphics protocol, so there is no sharper version
# of it to reach for. The still frame above stays because a single frame at
# that size still says what the video is; motion at that size does not.
#
# Every stream of output is closed off. A detached player that kept stdout or
# stderr would write over the result list from behind fzf, which is where the
# stack of unattributable errors came from: nothing on screen said which result
# was complaining, or that a player was complaining at all.
# The page URL goes to the player untouched, and that is the point rather than
# an omission. This used to pre-resolve with `yt-dlp --get-url` and hand over a
# direct stream, which capped playback at 720p by construction: --get-url can
# only return a progressive format, and on YouTube everything above 720p exists
# only as separate DASH video and audio the player has to merge itself. No
# choice of -f fixes that, so the resolve had to go rather than be retuned.
# Given the URL, mpv applies the ytdl-format chain in the user's own mpv.conf,
# which is where the quality preference belongs.
play_detached() {
	local file=$1 url=$2 player args=() log pid rc=0 reason i
	player=${DDGX_PLAYER:-mpv}
	if ! command -v "$player" >/dev/null 2>&1; then
		set_note "$file" "$player not found: set DDGX_PLAYER"
		return 0
	fi
	read -ra args <<<"${DDGX_PLAYER_ARGS:-}" || true

	# A log file rather than /dev/null. Nothing here may reach the terminal, or
	# it paints over the result list from behind fzf, which is where the stack
	# of unattributable errors came from. But a player that dies on the URL has
	# the only account of why, and discarding it is how a key comes to report
	# "playing" over a window that never appeared.
	mkdir -p "$CACHE_DIR"
	log="$CACHE_DIR/player.log"
	nohup "$player" "${args[@]}" "$url" >"$log" 2>&1 &
	pid=$!

	# A launch that is going to fail outright fails at once, before a window is
	# mapped, so a short bounded look is enough to tell that from a launch that
	# took. It is deliberately not a wait for playback to start: the player
	# resolves the URL itself and that takes seconds, which is time the picker
	# is not going to spend frozen. A failure that arrives after this window
	# belongs to the player's own window, where the user is already looking.
	for ((i = 0; i < 4; i++)); do
		kill -0 "$pid" 2>/dev/null || break
		sleep 0.25
	done
	if kill -0 "$pid" 2>/dev/null; then
		# A detached launch is otherwise completely silent, and a key that looks
		# like it did nothing is a key you press again.
		set_note "$file" "playing in $player"
		return 0
	fi

	wait "$pid" 2>/dev/null || rc=$?
	if [[ $rc -eq 0 ]]; then
		set_note "$file" "$player exited straight away"
		return 0
	fi
	# The player's own words. A guess here would repeat the mistake the extract
	# failures used to make: a generic "cannot play" sends you looking at the
	# player when the answer is that the video is private.
	reason=$(grep -m1 . "$log" 2>/dev/null || true)
	[[ -z $reason ]] && reason="$player exited $rc"
	set_note "$file" "cannot play: $reason"
}

# The picker's rows: the result index, then a numbered title with its domain.
# A mode of its own because a refinement re-runs it through fzf's reload.
#
# Two numberings. A web result is numbered by position, because position is all
# it has. An answer's source carries the number the answer itself used, so a
# claim marked [4] and the row that backs it agree. The answer row has no
# number and no domain: it is not somewhere you can go.
mode_list() {
	jq -r 'to_entries[] | "\(.key)\t\(.value.title)\t\(.value.url)\t\(.value.ref // "")"' "$1" |
		awk -F'\t' '{
			if ($3 == "") {
				printf "%s\t\033[1;35m▌ %s\033[0m\n", $1, $2
				next
			}
			split($3, parts, "/")
			label = ($4 == "" ? sprintf("%2d.", $1 + 1) : sprintf("[%s]", $4))
			printf "%s\t%s %s  \033[90m[%s]\033[0m\n", $1, label, $2, parts[3]
		}'
}

# The header: the query on top, the keys under it. The query is there because
# after two refinements the constraints in force are no longer something you
# can be expected to hold in your head. A note from the last action rides along
# on the same line and is cleared once shown, so it reads as what just
# happened rather than as part of the query.
mode_header() {
	local file=$1 note nf label='query'
	nf=$(note_file "$file")
	# Which engine answered is part of what the header is for: after a switch
	# through alt-q the same words mean two different things.
	[[ $(current_engine "$file") == pplx ]] && label='ask'
	printf '%s: %s' "$label" "$(current_query "$file")"
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

	choice=$(refine_menu "$file" | fzf --layout=reverse --prompt='refine > ' \
		--header="query: $query") || return 0
	choice=${choice%% *}

	if [[ $choice == follow ]]; then
		mode_follow "$file" "$num"
		return 0
	fi

	# The engine switches run the query as it stands, so they return here rather
	# than falling through to the equality check below, which exists to stop a
	# query that did not change from costing a search. Changing engine changes
	# the answer even when the words are identical, which is the whole point.
	case $choice in
	'ask' | 'web')
		local engine=ddgr
		[[ $choice == ask ]] && engine=pplx
		if [[ $engine == "$(current_engine "$file")" ]]; then
			set_note "$file" "already $choice"
			return 0
		fi
		# The bare words, without the operators. site: and filetype: are
		# DuckDuckGo syntax; handing them to an answer engine asks it to explain
		# a search operator rather than to answer the question.
		[[ $engine == pplx ]] && query=$(query_reset "$query")
		if [[ -z ${query//[[:space:]]/} ]]; then
			set_note "$file" 'nothing left to ask once the operators come off'
			return 0
		fi
		run_query "$file" "$num" "$query" "$engine"
		return 0
		;;
	esac

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
	local file=$1 count width lines i url title abstract cached ref label
	count=$(jq 'length' "$file")
	width=${DUMP_WIDTH:-100}
	lines=$DUMP_LINES

	prefetch "$file"
	wait "$PREFETCH_PID" 2>/dev/null || true

	for ((i = 0; i < count; i++)); do
		url=$(result_field "$i" "$file" url)
		title=$(result_field "$i" "$file" title)
		abstract=$(result_field "$i" "$file" abstract)

		# The answer row, dumped as the answer rather than as a result with no
		# page behind it. This is the path a pipe takes, so `-a -d question`
		# prints the answer and then the sources under it.
		if [[ -z $url ]]; then
			printf '\033[1;35m%s\033[0m\n\n' "$title"
			if [[ -s $(answer_file "$file") ]]; then
				sed 's/^/   /' "$(answer_file "$file")"
			fi
			printf '\n'
			continue
		fi

		# Numbered the way the picker numbers it: an answer's source keeps the
		# number the answer cited it by.
		ref=$(result_field "$i" "$file" ref)
		if [[ -n $ref ]]; then
			label="[$ref]"
		else
			label="$((i + 1))."
		fi
		printf '\033[1;36m%s %s\033[0m\n' "$label" "$title"
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

	# ctrl-o is a transform rather than an execute: mode_action prints the fzf
	# actions and fzf performs them, which is how one key reaches the pager, the
	# renderer and the preview-pane player. Its stderr goes to /dev/null because
	# anything a dispatcher prints outside that action list is noise landing on
	# the picker, and the pane is where a reason belongs.
	selected=$(
		mode_list "$file" |
			fzf --ansi --multi \
				--delimiter=$'\t' --with-nth=2.. \
				--prompt='result > ' \
				--header="$(mode_header "$file")" \
				--preview="$SELF --preview '$file' {1}" \
				--preview-window='right,58%,wrap,border-left' \
				--bind="enter:transform($SELF --enter '$file' {1} $num 2>/dev/null)" \
				--bind="ctrl-o:transform($SELF --action '$file' {1} {+1} 2>/dev/null)" \
				--bind="ctrl-e:execute($SELF --edit '$file' {+1})" \
				--bind="ctrl-a:execute-silent($SELF --bookmark '$file' {+1})+transform-header($SELF --header '$file')" \
				--bind="alt-h:transform($SELF --send '$file' {+1} 2>/dev/null)" \
				--bind="ctrl-y:execute-silent($SELF --copy '$file' {+1})" \
				--bind="ctrl-r:execute-silent($SELF --refetch '$file' {+1})+refresh-preview" \
				--bind="alt-q:execute($SELF --refine '$file' $num)+reload($SELF --list '$file')+transform-header($SELF --header '$file')" \
				--bind='ctrl-v:change-preview-window(hidden|right,58%,wrap,border-left)' \
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
	local num="${DDGX_NUM:-8}" dump=0 failed=0 args=() engine=ddgr query
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
	--send)
		shift
		mode_send "$@"
		return 0
		;;
	--refetch)
		shift
		mode_refetch "$@"
		return 0
		;;
	--action)
		shift
		mode_action "$@"
		return 0
		;;
	--enter)
		shift
		mode_enter "$@"
		return 0
		;;
	--follow)
		shift
		mode_follow "$@"
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

	# Past this point we are the top-level run, not a re-entrant call from an
	# fzf binding. Take the hand-off target NOW, before prompt_for_query blocks
	# on a human typing: the binding wrote it microseconds ago, and any popup
	# opened from a second attached client meanwhile would overwrite it. Clear
	# it in the same breath so an abandoned popup cannot leave a live pane id
	# lying in a global for the next run to find and quietly deliver into.
	SOURCE_PANE=$(popup_source_pane)
	clear_popup_source_pane

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
		-a | --ask)
			engine=pplx
			shift
			;;
		--preset)
			engine=pplx
			PPLX_PRESET=$2
			shift 2
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

	# Whatever shape the query arrived in, it is one string from here on. The
	# leading ? is a mode, not a search term: DuckDuckGo has no ? operator, so
	# nothing that used to be a query loses meaning by being read this way.
	query="${args[*]}"
	if [[ $query == '?'* ]]; then
		engine=pplx
		# A second ? asks harder. One mark for the question you ask in passing,
		# two for the one you sit with, which is the only depth decision worth
		# making at the moment of typing.
		if [[ $query == '??'* ]]; then
			PPLX_PRESET="$PPLX_DEEP_PRESET"
			query="${query#\?\?}"
		else
			query="${query#\?}"
		fi
		query="${query#"${query%%[![:space:]]*}"}"
	fi
	if [[ -z ${query//[[:space:]]/} ]]; then
		die "nothing to search for"
	fi

	# ddgr is only needed by the engine that uses it: asking for an answer on a
	# machine without ddgr installed is a working path, and demanding it here
	# would refuse a search this script can perform.
	if [[ $engine == pplx ]]; then
		[[ -x $ASK_CMD ]] || die "missing ask backend: $ASK_CMD"
	else
		command -v ddgr >/dev/null 2>&1 || die "ddgr not found"
	fi
	command -v jq >/dev/null 2>&1 || die "jq not found"
	command -v node >/dev/null 2>&1 || die "node not found"
	[[ -f $READABLE ]] || die "missing extractor: $READABLE"
	engine_ready || die "extraction engine missing: run ${SELF##*/} --setup"

	RESULTS_FILE=$(mktemp -t ddgx-results-XXXXXX.json)
	trap cleanup EXIT INT TERM
	printf '%s' "$SOURCE_PANE" >"$(target_file "$RESULTS_FILE")"

	# The query round-trip is the one unavoidable wait, so say it is happening
	# instead of leaving a blank screen. An ask waits longer than a search, and
	# says which engine is taking the time.
	if [[ -t 1 ]]; then
		if [[ $engine == pplx ]]; then
			printf '\033[90m  asking perplexity (%s) about %s ...\033[0m\r' \
				"$PPLX_PRESET" "$query" >&2
		else
			printf '\033[90m  searching for %s ...\033[0m\r' "$query" >&2
		fi
	fi
	# Wipe that line whichever way the search went: a reason printed over a
	# half-erased "searching for ..." is how "HTTP Error 202: Acceptedes
	# finalizers ..." reaches the screen.
	failed=0
	if [[ $engine == pplx ]]; then
		search_pplx "$RESULTS_FILE" "$query" "$(answer_file "$RESULTS_FILE")" \
			"$(thread_file "$RESULTS_FILE")" || failed=1
	else
		search_ddgr "$RESULTS_FILE" "$num" "$query" || failed=1
	fi
	if [[ -t 1 ]]; then
		printf '\033[2K\r' >&2
	fi
	if [[ $failed -eq 1 ]]; then
		die "$SEARCH_ERROR"
	fi
	# What the picker refines from, and what it refines through.
	printf '%s\n' "$query" >"$(query_file "$RESULTS_FILE")"
	set_engine "$RESULTS_FILE" "$engine"

	if [[ $dump -eq 1 ]] || [[ ! -t 1 ]]; then
		# Piped without -d: dump rather than start fzf on a headless stdout.
		mode_dump "$RESULTS_FILE"
	else
		mode_pick "$RESULTS_FILE" "$num"
	fi
}

main "$@"
