#!/usr/bin/env bats
#
# Covers the search hybrid: __readable.mjs (Mozilla Readability + Turndown)
# and __ddgx.sh's result rendering. No test fetches over the network: the
# extractor is fed local fixtures, ddgr is stubbed, and the dump/preview modes
# read a pre-seeded cache.

setup() {
	REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	READABLE="$REPO_ROOT/scripts/__readable.mjs"
	DDGX="$REPO_ROOT/scripts/__ddgx.sh"
	FIXTURES="$BATS_TEST_TMPDIR/fixtures"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	CACHE_HOME="$BATS_TEST_TMPDIR/cache"
	DATA_HOME="$BATS_TEST_TMPDIR/data"
	mkdir -p "$FIXTURES" "$STUB_BIN" "$CACHE_HOME" "$DATA_HOME"

	# Point at a file that does not exist so the suite renders with
	# MarkDownload's stock settings rather than whatever this machine's
	# exported ones happen to be.
	export DDGX_OPTIONS="$BATS_TEST_TMPDIR/absent-options.json"

	MODULES_DIR="${DDGX_MODULES:-$HOME/.local/share/ddgx}"
	if [ ! -d "$MODULES_DIR/node_modules/@mozilla/readability" ]; then
		skip "extraction engine not installed (run __ddgx.sh --setup)"
	fi
}

# A page shaped like the real thing: chrome wrapped around an article.
write_article_fixture() {
	cat >"$FIXTURES/article.html" <<'HTML'
<!doctype html>
<html><head><title>Draining a node safely</title>
<script>var tracking = 1;</script>
<style>body { color: red; }</style>
</head>
<body>
  <nav class="site-nav"><a href="/">Home</a><a href="/blog">Blog</a></nav>
  <header class="page-header"><a href="/login">Sign in</a></header>
  <article>
    <h1>Draining a node safely</h1>
    <p>Cordoning a node marks it unschedulable so the scheduler stops placing
       new pods on it, which is the first step before any maintenance window.</p>
    <p>Draining then evicts the pods that are already running there, honouring
       any pod disruption budgets that the workloads declare for themselves.</p>
    <p>Marking a node is <strong>safe</strong> and entirely <em>reversible</em>, which
       matters because this sentence is deliberately long enough to prove that
       nothing downstream rewraps the markdown it is handed.</p>
    <p>The rest of the procedure lives in the <a href="#aftercare">aftercare
       section</a> further down, and the machine it runs against is described
       in the <a class="glossary-tooltip" data-bs-toggle="tooltip"
       title="A worker machine, part of a cluster, that runs pods."
       href="/docs/nodes/">node</a> reference page.</p>
    <ul>
      <li><p>Cordon the node first, always.</p></li>
      <li>Then drain it with a timeout.</li>
    </ul>
    <pre><code>kubectl drain node-1 --ignore-daemonsets</code></pre>
    <table>
      <thead><tr><th>Field</th><th>Meaning</th></tr></thead>
      <tbody><tr><td>replicas</td><td>desired count</td></tr></tbody>
    </table>
  </article>
  <aside class="related-posts"><a href="/x">You may also like this other post</a></aside>
  <div class="newsletter-signup">Subscribe to our weekly newsletter today</div>
  <footer>Copyright 2026, all rights reserved by the company</footer>
</body></html>
HTML
}

extract_fixture() {
	run node "$READABLE" --file "$FIXTURES/article.html" \
		--url https://example.com/post "$@"
}

# --------------------------------------------------------------------------
# __readable.mjs
# --------------------------------------------------------------------------

@test "extractor keeps article prose" {
	write_article_fixture
	extract_fixture --width 100

	[ "$status" -eq 0 ]
	[[ "$output" == *"Cordoning a node marks it unschedulable"* ]]
	[[ "$output" == *"honouring"* ]]
}

@test "extractor drops nav, related, newsletter, footer and scripts" {
	write_article_fixture
	extract_fixture --width 100

	[ "$status" -eq 0 ]
	[[ "$output" != *"You may also like"* ]]
	[[ "$output" != *"Subscribe to our weekly newsletter"* ]]
	[[ "$output" != *"all rights reserved"* ]]
	[[ "$output" != *"tracking"* ]]
	[[ "$output" != *"color: red"* ]]
}

@test "extractor uses MarkDownload's emphasis delimiters" {
	write_article_fixture
	extract_fixture

	# Verified against deathau/markdownload src/shared/default-options.js:
	# strongDelimiter "**", emDelimiter "_".
	[ "$status" -eq 0 ]
	[[ "$output" == *"**safe**"* ]]
	[[ "$output" == *"_reversible_"* ]]
}

@test "extractor renders tables as GFM" {
	write_article_fixture
	extract_fixture

	# MarkDownload loads turndown-plugin-gfm; without it a table collapses
	# into a run-on line.
	[ "$status" -eq 0 ]
	[[ "$output" == *"| Field | Meaning |"* ]]
	[[ "$output" == *"| --- | --- |"* ]]
	[[ "$output" == *"| replicas | desired count |"* ]]
}

@test "extractor takes its settings from the extension's export" {
	write_article_fixture
	cat >"$DDGX_OPTIONS" <<'JSON'
{ "bulletListMarker": "*", "emDelimiter": "*", "headingStyle": "setext" }
JSON
	extract_fixture

	# The settings are the extension's, not a second copy living in our code.
	[ "$status" -eq 0 ]
	grep -qE '^\* +Cordon the node first' <<<"$output"
	[[ "$output" == *"*reversible*"* ]]
}

@test "extractor resolves same-page anchors against the page url" {
	write_article_fixture
	extract_fixture

	# MarkDownload's links rule rewrites every href through validateUri.
	# Readability leaves same-page anchors alone, so without that rule this
	# arrives as a bare "#aftercare" with no page attached to it.
	[ "$status" -eq 0 ]
	[[ "$output" == *"(https://example.com/post#aftercare)"* ]]
	[[ "$output" == *"(https://example.com/docs/nodes/"* ]]
}

@test "extractor assumes https for a bare host" {
	write_article_fixture
	run node "$READABLE" --file "$FIXTURES/article.html" --url example.com

	# "2md cloudrumble.net" is how anyone types a url by hand. Without a
	# scheme new URL() throws before anything is fetched.
	[ "$status" -eq 0 ]
	[[ "$output" == *"(https://example.com/docs/nodes/)"* ]]
}

@test "extractor drops the titles a tooltip library would have consumed" {
	write_article_fixture
	extract_fixture

	# Bootstrap moves title into a data- attribute when it initialises, so the
	# live DOM the extension reads carries none. We read the served HTML,
	# where the whole glossary definition is still sitting in the attribute.
	[ "$status" -eq 0 ]
	[[ "$output" != *"A worker machine, part of a cluster"* ]]
	[[ "$output" == *"[node](https://example.com/docs/nodes/)"* ]]
}

@test "extractor ends where the article ends" {
	write_article_fixture
	extract_fixture

	# MarkDownload's own files stop on the last character. Terminating the
	# line is the printing end's job, so a redirect here is byte-comparable
	# against an export from the extension.
	[ "$status" -eq 0 ]
	local raw
	raw=$(node "$READABLE" --file "$FIXTURES/article.html" \
		--url https://example.com/post | tail -c 1)
	[ -n "$raw" ]
}

@test "extractor renders lists and fenced code" {
	write_article_fixture
	extract_fixture

	[ "$status" -eq 0 ]
	grep -qE '^- +Cordon the node first' <<<"$output"
	[[ "$output" == *'```'* ]]
	[[ "$output" == *"kubectl drain node-1 --ignore-daemonsets"* ]]
}

@test "extractor emits nested list text once" {
	write_article_fixture
	extract_fixture --width 100

	[ "$status" -eq 0 ]
	[ "$(grep -c 'Cordon the node first' <<<"$output")" -eq 1 ]
}

@test "extractor hands back markdown unaltered, without rewrapping" {
	write_article_fixture
	extract_fixture

	# Wrapping is the delivery end's job: fzf's preview window soft-wraps and
	# a pipe should receive exactly what Turndown produced. Rewrapping here is
	# what desynced list markers from their unwrapped siblings.
	[ "$status" -eq 0 ]
	local longest=0 line
	while IFS= read -r line; do
		[ "${#line}" -gt "$longest" ] && longest=${#line}
	done <<<"$output"
	[ "$longest" -gt 100 ]
}

@test "extractor writes lists with a single space and no whitespace-only lines" {
	write_article_fixture
	extract_fixture

	# The one deliberate departure from the extension. Turndown's listItem
	# rule hardcodes marker plus three spaces and indents continuation lines
	# to match, which leaves a line of nothing but spaces between items.
	# bulletListMarker only picks the character, so this needs the rule.
	[ "$status" -eq 0 ]
	local item
	while IFS= read -r item; do
		[[ "$item" == "- "* ]]
		[[ "$item" != "-  "* ]]
	done < <(grep '^-' <<<"$output")
	! grep -qE '^[[:blank:]]+$' <<<"$output"
}

@test "extractor caps output with --max-lines" {
	write_article_fixture
	extract_fixture --width 100 --max-lines 3

	[ "$status" -eq 0 ]
	[ "${lines[-1]}" = "..." ]
	[[ "$output" != *"kubectl drain"* ]]
}

@test "extractor reports how much of the page it kept" {
	write_article_fixture
	extract_fixture --width 100 --stats

	[ "$status" -eq 0 ]
	grep -qE '\[kept [0-9]+ of [0-9]+ characters of page text\]' <<<"$output"
}

@test "extractor refuses non-http schemes" {
	run node "$READABLE" --url "file:///etc/passwd"

	[ "$status" -eq 1 ]
	[[ "$output" == *"unsupported scheme"* ]]
}

@test "extractor fails on a page with no article" {
	printf '<html><body><nav>Home</nav></body></html>\n' >"$FIXTURES/empty.html"

	run node "$READABLE" --file "$FIXTURES/empty.html" --url https://example.com/

	[ "$status" -eq 1 ]
	[[ "$output" == *"["* ]] # a bracketed reason on stderr
}

@test "batch mode leaves already-cached extracts alone" {
	printf '%s\n' '[{"title":"A","url":"https://cached.example/a"}]' \
		>"$BATS_TEST_TMPDIR/results.json"
	local key cachedir="$BATS_TEST_TMPDIR/batchcache"
	mkdir -p "$cachedir"
	key=$(printf '%s' "https://cached.example/a" | sha1sum | cut -d' ' -f1)
	printf 'PRESEEDED\n' >"$cachedir/$key.txt"

	run node "$READABLE" --batch "$BATS_TEST_TMPDIR/results.json" \
		--cache "$cachedir" --width 80

	[ "$status" -eq 0 ]
	[ "$(cat "$cachedir/$key.txt")" = "PRESEEDED" ]
}

# --------------------------------------------------------------------------
# __ddgx.sh
# --------------------------------------------------------------------------

# Stub ddgr so no query leaves the machine.
stub_ddgr() {
	cat >"$STUB_BIN/ddgr" <<EOF
#!/usr/bin/env bash
cat <<'JSON'
$1
JSON
EOF
	chmod +x "$STUB_BIN/ddgr"
}

# Seed the extract cache for a URL. The key is the sha1 of the URL, which is
# the contract both __ddgx.sh's cache_file() and the batch writer implement.
seed_cache() {
	local url=$1 body=$2 key
	key=$(printf '%s' "$url" | sha1sum | cut -d' ' -f1)
	mkdir -p "$CACHE_HOME/ddgx"
	printf '%s\n' "$body" >"$CACHE_HOME/ddgx/$key.txt"
}

run_ddgx() {
	run env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" \
		XDG_DATA_HOME="$DATA_HOME" DDGX_TTL=0 bash "$DDGX" "$@"
}

@test "dump mode prints title, url, snippet and page extract" {
	stub_ddgr '[{"title":"Draining nodes","url":"https://example.com/drain","abstract":"How to drain a node."}]'
	seed_cache "https://example.com/drain" "# Draining nodes
Cordon before you drain."

	run_ddgx -d "drain node"

	[ "$status" -eq 0 ]
	[[ "$output" == *"1. Draining nodes"* ]]
	[[ "$output" == *"https://example.com/drain"* ]]
	[[ "$output" == *"How to drain a node."* ]]
	[[ "$output" == *"Cordon before you drain."* ]]
}

@test "dump mode caps the extract at --lines and marks the cut" {
	stub_ddgr '[{"title":"Long","url":"https://example.com/long","abstract":"s"}]'
	seed_cache "https://example.com/long" "line one
line two
line three
line four"

	run_ddgx -d -l 2 "long"

	[ "$status" -eq 0 ]
	[[ "$output" == *"line one"* ]]
	[[ "$output" == *"line two"* ]]
	[[ "$output" != *"line three"* ]]
	[[ "$output" == *"..."* ]]
}

@test "dump mode reports results whose text could not be extracted" {
	stub_ddgr '[{"title":"Blocked","url":"https://blocked.invalid/x","abstract":"nope"}]'

	run_ddgx -d "blocked"

	[ "$status" -eq 0 ]
	[[ "$output" == *"Blocked"* ]]
	[[ "$output" == *"no page text"* ]]
}

@test "dump mode renders every result" {
	stub_ddgr '[{"title":"First","url":"https://example.com/1","abstract":"a"},{"title":"Second","url":"https://example.com/2","abstract":"b"}]'
	seed_cache "https://example.com/1" "first body"
	seed_cache "https://example.com/2" "second body"

	run_ddgx -d "two results"

	[ "$status" -eq 0 ]
	[[ "$output" == *"1. First"* ]]
	[[ "$output" == *"2. Second"* ]]
	[[ "$output" == *"first body"* ]]
	[[ "$output" == *"second body"* ]]
}

@test "empty result set exits with a message" {
	stub_ddgr '[]'

	run_ddgx -d "nothing matches this"

	[ "$status" -eq 1 ]
	[[ "$output" == *"No results."* ]]
}

@test "no query prints usage and exits non-zero" {
	run_ddgx

	[ "$status" -eq 1 ]
	[[ "$output" == *"__ddgx.sh"* ]]
}

@test "preview mode renders one result for fzf" {
	seed_cache "https://example.com/p" "the extracted body text"
	local results="$BATS_TEST_TMPDIR/results.json"
	printf '%s\n' '[{"title":"Preview me","url":"https://example.com/p","abstract":"the snippet"}]' >"$results"

	run env XDG_CACHE_HOME="$CACHE_HOME" DDGX_TTL=0 FZF_PREVIEW_COLUMNS=80 \
		bash "$DDGX" --preview "$results" 0

	[ "$status" -eq 0 ]
	[[ "$output" == *"Preview me"* ]]
	[[ "$output" == *"https://example.com/p"* ]]
	[[ "$output" == *"the snippet"* ]]
	[[ "$output" == *"the extracted body text"* ]]
}

# --------------------------------------------------------------------------
# Marked-set actions. fzf passes {+1}, every marked index, so these modes take
# a results file followed by one or more indices.
# --------------------------------------------------------------------------

write_two_results() {
	printf '%s\n' '[{"title":"First hit","url":"https://example.com/1","abstract":"a"},{"title":"Second hit","url":"https://example.com/2","abstract":"b"}]' \
		>"$BATS_TEST_TMPDIR/results.json"
	seed_cache "https://example.com/1" "body of the first page"
	seed_cache "https://example.com/2" "body of the second page"
}

@test "edit mode scaffolds a markdown note per marked result" {
	write_two_results
	printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/opened.txt"\n' \
		"$BATS_TEST_TMPDIR" >"$STUB_BIN/fake-editor"
	chmod +x "$STUB_BIN/fake-editor"

	run env XDG_CACHE_HOME="$CACHE_HOME" XDG_DATA_HOME="$DATA_HOME" DDGX_TTL=0 \
		DDGX_EDITOR="$STUB_BIN/fake-editor" \
		bash "$DDGX" --edit "$BATS_TEST_TMPDIR/results.json" 0 1

	[ "$status" -eq 0 ]
	[ "$(wc -l <"$BATS_TEST_TMPDIR/opened.txt")" -eq 2 ]

	local first
	first=$(head -n1 "$BATS_TEST_TMPDIR/opened.txt")
	[[ "$first" == *"first-hit.md" ]]
	grep -q '^# First hit' "$first"
	grep -q '^Source: https://example.com/1' "$first"
	grep -q 'body of the first page' "$first"
}

@test "edit mode keeps notes already edited" {
	write_two_results
	printf '#!/usr/bin/env bash\ntrue\n' >"$STUB_BIN/fake-editor"
	chmod +x "$STUB_BIN/fake-editor"

	run env XDG_CACHE_HOME="$CACHE_HOME" XDG_DATA_HOME="$DATA_HOME" DDGX_TTL=0 \
		DDGX_EDITOR="$STUB_BIN/fake-editor" \
		bash "$DDGX" --edit "$BATS_TEST_TMPDIR/results.json" 0
	[ "$status" -eq 0 ]

	echo "my own notes" >>"$DATA_HOME/ddgx/notes/first-hit.md"

	run env XDG_CACHE_HOME="$CACHE_HOME" XDG_DATA_HOME="$DATA_HOME" DDGX_TTL=0 \
		DDGX_EDITOR="$STUB_BIN/fake-editor" \
		bash "$DDGX" --edit "$BATS_TEST_TMPDIR/results.json" 0

	[ "$status" -eq 0 ]
	grep -q 'my own notes' "$DATA_HOME/ddgx/notes/first-hit.md"
}

@test "read mode concatenates every marked extract" {
	write_two_results
	run env XDG_CACHE_HOME="$CACHE_HOME" DDGX_TTL=0 \
		bash -c "bash '$DDGX' --read '$BATS_TEST_TMPDIR/results.json' 0 1 | cat"

	[ "$status" -eq 0 ]
	[[ "$output" == *"body of the first page"* ]]
	[[ "$output" == *"body of the second page"* ]]
	[[ "$output" == *"Source: https://example.com/1"* ]]
	[[ "$output" == *"Source: https://example.com/2"* ]]
}

@test "bookmark mode writes a pet snippet per marked result" {
	if ! command -v expect >/dev/null 2>&1 || ! command -v pet >/dev/null 2>&1; then
		skip "expect or pet not installed"
	fi
	write_two_results
	local links="$BATS_TEST_TMPDIR/pet-links.toml"
	: >"$links"

	run env XDG_CACHE_HOME="$CACHE_HOME" DDGX_PET_FILE="$links" \
		bash "$DDGX" --bookmark "$BATS_TEST_TMPDIR/results.json" 0 1

	[ "$status" -eq 0 ]
	[ "$(grep -c '^\[\[Snippets\]\]' "$links")" -eq 2 ]
	grep -q 'Description = "Link to First hit"' "$links"
	grep -q 'command = "xdg-open https://example.com/1"' "$links"
	grep -q 'Tag = \["link"\]' "$links"
}

@test "bookmark mode does not add a url twice" {
	if ! command -v expect >/dev/null 2>&1 || ! command -v pet >/dev/null 2>&1; then
		skip "expect or pet not installed"
	fi
	write_two_results
	local links="$BATS_TEST_TMPDIR/pet-links.toml"
	: >"$links"

	env XDG_CACHE_HOME="$CACHE_HOME" DDGX_PET_FILE="$links" \
		bash "$DDGX" --bookmark "$BATS_TEST_TMPDIR/results.json" 0
	run env XDG_CACHE_HOME="$CACHE_HOME" DDGX_PET_FILE="$links" \
		bash "$DDGX" --bookmark "$BATS_TEST_TMPDIR/results.json" 0

	[ "$status" -eq 0 ]
	[ "$(grep -c '^\[\[Snippets\]\]' "$links")" -eq 1 ]
}

@test "piped output falls back to dump mode without -d" {
	stub_ddgr '[{"title":"Piped","url":"https://example.com/piped","abstract":"a"}]'
	seed_cache "https://example.com/piped" "piped body"

	run_ddgx "piped query"

	[ "$status" -eq 0 ]
	[[ "$output" == *"1. Piped"* ]]
	[[ "$output" == *"piped body"* ]]
}

# --------------------------------------------------------------------------
# Refining the query. ctrl-s in the picker runs --refine, which rewrites the
# query and the results in place so fzf can reload over the same files.
# --------------------------------------------------------------------------

# Stub fzf so a menu choice and a value pick are two lines of a queue. Each
# call records what it was offered, which is how the site: values are checked
# against the result set they are supposed to come from. A queued "@abort"
# stands for esc.
stub_fzf() {
	printf '%s\n' "$@" >"$STUB_BIN/fzf.queue"
	rm -f "$STUB_BIN/fzf.count"
	cat >"$STUB_BIN/fzf" <<'EOF'
#!/usr/bin/env bash
dir=$(dirname "$0")
n=$(cat "$dir/fzf.count" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" >"$dir/fzf.count"
cat >"$dir/fzf.stdin.$n"
line=$(sed -n "${n}p" "$dir/fzf.queue")
[ "$line" = "@abort" ] && exit 130
printf '%s\n' "$line"
EOF
	chmod +x "$STUB_BIN/fzf"
}

# A picker mid-search: three results over two domains, and the query that
# produced them.
write_search_state() {
	RESULTS="$BATS_TEST_TMPDIR/results.json"
	printf '%s\n' '[{"title":"Finalizers","url":"https://kubernetes.io/docs/finalizers/","abstract":"a"},{"title":"A blog","url":"https://www.medium.com/p/1","abstract":"b"},{"title":"Nodes","url":"https://kubernetes.io/docs/nodes/","abstract":"c"}]' >"$RESULTS"
	printf '%s\n' "$1" >"$RESULTS.query"
	# The refined set, pre-cached so the warming pass has nothing to fetch.
	seed_cache "https://kubernetes.io/only/" "the narrowed page"
}

refined_query() { head -n1 "$RESULTS.query"; }

run_refine() {
	run env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" \
		XDG_DATA_HOME="$DATA_HOME" DDGX_TTL=0 \
		bash "$DDGX" --refine "$RESULTS" 8
}

@test "refining by site: rewrites the query and the results under it" {
	write_search_state 'kubernetes finalizers'
	stub_ddgr '[{"title":"Narrowed","url":"https://kubernetes.io/only/","abstract":"z"}]'
	stub_fzf 'site:' 'kubernetes.io'

	run_refine

	[ "$status" -eq 0 ]
	[ "$(refined_query)" = "kubernetes finalizers site:kubernetes.io" ]
	[ "$(jq -r '.[0].title' "$RESULTS")" = "Narrowed" ]
	[ "$(jq 'length' "$RESULTS")" -eq 1 ]
}

@test "the site: values on offer are the domains the results came from" {
	write_search_state 'kubernetes finalizers'
	stub_ddgr '[{"title":"Narrowed","url":"https://kubernetes.io/only/","abstract":"z"}]'
	stub_fzf 'site:' 'kubernetes.io'

	run_refine

	# Picking a domain out of a list beats typing one, and the list is the
	# result set's own domains, commonest first, with www dropped.
	[ "$status" -eq 0 ]
	local offered="$STUB_BIN/fzf.stdin.2"
	[ "$(head -n1 "$offered")" = "kubernetes.io" ]
	grep -qx 'medium.com' "$offered"
	! grep -q 'www\.' "$offered"
}

@test "refining site: twice replaces it rather than adding a second one" {
	write_search_state 'kubernetes finalizers site:medium.com'
	stub_ddgr '[{"title":"Narrowed","url":"https://kubernetes.io/only/","abstract":"z"}]'
	stub_fzf 'site:' 'kubernetes.io'

	run_refine

	# Two site: terms in one query match nothing at all.
	[ "$status" -eq 0 ]
	[ "$(refined_query)" = "kubernetes finalizers site:kubernetes.io" ]
}

@test "an empty value takes the operator back off the query" {
	write_search_state 'kubernetes finalizers site:medium.com'
	stub_ddgr '[{"title":"Widened","url":"https://kubernetes.io/only/","abstract":"z"}]'
	stub_fzf 'site:' ''

	run_refine

	[ "$status" -eq 0 ]
	[ "$(refined_query)" = "kubernetes finalizers" ]
}

@test "an abandoned menu leaves the query and the results alone" {
	write_search_state 'kubernetes finalizers'
	stub_ddgr '[{"title":"Never asked for","url":"https://kubernetes.io/only/","abstract":"z"}]'
	stub_fzf '@abort'

	run_refine

	[ "$status" -eq 0 ]
	[ "$(refined_query)" = "kubernetes finalizers" ]
	[ "$(jq 'length' "$RESULTS")" -eq 3 ]
}

@test "a refinement that finds nothing keeps the previous results" {
	write_search_state 'kubernetes finalizers'
	stub_ddgr '[]'
	stub_fzf 'site:' 'nowhere.example'

	run_refine

	# An empty picker with the query already spent is a dead end: the point of
	# refining is to try another constraint against the set you can still see.
	[ "$status" -eq 0 ]
	[ "$(refined_query)" = "kubernetes finalizers" ]
	[ "$(jq 'length' "$RESULTS")" -eq 3 ]
	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --header "$RESULTS"
	[[ "$output" == *"kept the previous results"* ]]
}

@test "reset drops every operator and keeps the words" {
	write_search_state 'kubernetes drain site:medium.com filetype:pdf -aws "exact words"'
	stub_ddgr '[{"title":"Widened","url":"https://kubernetes.io/only/","abstract":"z"}]'
	stub_fzf 'reset'

	run_refine

	[ "$status" -eq 0 ]
	[ "$(refined_query)" = "kubernetes drain" ]
}

@test "an excluded word is appended, and more than one may be" {
	write_search_state 'kubernetes drain -aws'
	stub_ddgr '[{"title":"Narrowed","url":"https://kubernetes.io/only/","abstract":"z"}]'
	stub_fzf 'exclude'

	run env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" \
		XDG_DATA_HOME="$DATA_HOME" DDGX_TTL=0 \
		bash "$DDGX" --refine "$RESULTS" 8 <<<"azure"

	# Exclusions are not an operator with one value: every one you add says
	# something the last one did not.
	[ "$status" -eq 0 ]
	[ "$(refined_query)" = "kubernetes drain -aws -azure" ]
}

@test "the raw query stays editable by hand" {
	write_search_state 'kubernetes finalizers'
	stub_ddgr '[{"title":"Typed","url":"https://kubernetes.io/only/","abstract":"z"}]'
	stub_fzf 'edit'

	run env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" \
		XDG_DATA_HOME="$DATA_HOME" DDGX_TTL=0 \
		bash "$DDGX" --refine "$RESULTS" 8 <<<'etcd defrag intitle:runbook'

	# The builder must never become the only way to type a query.
	[ "$status" -eq 0 ]
	[ "$(refined_query)" = "etcd defrag intitle:runbook" ]
}

@test "list mode gives fzf one row per result, keyed by index" {
	write_search_state 'kubernetes finalizers'

	run bash "$DDGX" --list "$RESULTS"

	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 3 ]
	[[ "${lines[0]}" == "0	"* ]]
	[[ "${lines[0]}" == *"1. Finalizers"* ]]
	[[ "${lines[0]}" == *"[kubernetes.io]"* ]]
	[[ "${lines[2]}" == "2	"* ]]
}

@test "the header carries the query, and a note only until it is read" {
	write_search_state 'kubernetes finalizers site:kubernetes.io'
	printf 'bookmarked to pet-links.toml\n' >"$RESULTS.note"

	run bash "$DDGX" --header "$RESULTS"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == "query: kubernetes finalizers site:kubernetes.io"* ]]
	[[ "${lines[0]}" == *"bookmarked to pet-links.toml"* ]]
	[[ "${lines[1]}" == *"ctrl-s refine"* ]]

	# What just happened is not part of the query: it goes once it is shown.
	run bash "$DDGX" --header "$RESULTS"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" != *"bookmarked"* ]]
}
