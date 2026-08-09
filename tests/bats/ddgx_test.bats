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
	[[ "$output" == *"no results"* ]]
}

@test "a refused search says so instead of blaming the query" {
	# ddgr answers a throttled request with an empty set, exit 0, and the
	# reason on stderr. Reported as "no results" it sends you rewording a
	# query that was never the problem.
	cat >"$STUB_BIN/ddgr" <<'EOF'
#!/usr/bin/env bash
echo '[ERROR] HTTP Error 202: Accepted' >&2
echo '[]'
EOF
	chmod +x "$STUB_BIN/ddgr"

	run_ddgx -d "throttled"

	[ "$status" -eq 1 ]
	[[ "$output" == *"HTTP Error 202"* ]]
	[[ "$output" != *"[ERROR]"* ]]
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
# Refining the query. alt-q in the picker runs --refine, which rewrites the
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
	[[ "$output" == *"no results, kept the previous results"* ]]
}

@test "a refusal mid-refinement is not reported as an empty result set" {
	write_search_state 'kubernetes finalizers'
	cat >"$STUB_BIN/ddgr" <<'EOF'
#!/usr/bin/env bash
echo '[ERROR] HTTP Error 202: Accepted' >&2
echo '[]'
EOF
	chmod +x "$STUB_BIN/ddgr"
	stub_fzf 'site:' 'kubernetes.io'

	run_refine

	# Told "nothing for that", you drop a constraint that was fine. The header
	# has to name what actually happened.
	[ "$status" -eq 0 ]
	[ "$(refined_query)" = "kubernetes finalizers" ]
	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --header "$RESULTS"
	[[ "$output" == *"HTTP Error 202: Accepted, kept the previous results"* ]]
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

# --------------------------------------------------------------------------
# Media results, and the one key that acts on them.
#
# ctrl-o is contextual: it plays a video in the preview pane, renders a page
# whose text could not be extracted, or opens the marked extracts in a pager,
# and it decides which from the same state the preview pane drew itself from.
# It runs as fzf's transform action, so --action prints fzf actions rather than
# performing them, and the tests below read that printed list.
#
# is_media_url has no mode of its own, so these reach it by sourcing the script.
# --help makes main print the header block and return before it reaches mktemp
# or installs a trap, which leaves the functions defined and nothing else done.
# --------------------------------------------------------------------------

is_media() {
	run bash -c 'ddgx=$1; url=$2; source "$ddgx" --help >/dev/null 2>&1
		is_media_url "$url"' _ "$DDGX" "$1"
}

# The player is launched detached, so the script returns before the stub has
# necessarily written anything. Wait for the write instead of racing it.
wait_for_line_matching() {
	local path=$1 pattern=$2 i
	for ((i = 0; i < 50; i++)); do
		if grep -q "$pattern" "$path" 2>/dev/null; then
			return 0
		fi
		sleep 0.1
	done
	return 1
}

write_media_results() {
	printf '%s\n' '[{"title":"A conference talk","url":"https://www.youtube.com/watch?v=aaa111","abstract":"a"},{"title":"A short","url":"https://youtu.be/bbb222","abstract":"b"}]' \
		>"$BATS_TEST_TMPDIR/results.json"
	printf '%s\n' 'kubernetes talks' >"$BATS_TEST_TMPDIR/results.json.query"
}

# Write the sidecar __readable.mjs leaves beside a cache entry when a url turned
# out to hold a video or a playlist. Same key as seed_cache, the sha1 of the
# url, which is the contract the two sides find each other's writes through.
# Its presence is what makes a result playable, so a test that wants a video
# writes one and a test that wants a page does not.
seed_media() {
	local url=$1 title=$2 thumb=$3 key
	key=$(printf '%s' "$url" | sha1sum | cut -d' ' -f1)
	mkdir -p "$CACHE_HOME/ddgx"
	jq -n --arg t "$title" --arg th "$thumb" --arg w "$url" \
		'{kind:"video",title:$t,thumbnail:$th,webpage_url:$w,duration:213}' \
		>"$CACHE_HOME/ddgx/$key.media"
}

# The player, and a yt-dlp that exists only so a test can prove it is never
# called: ddgx must not pre-resolve, because --get-url can only return a
# progressive format and that caps playback at 720p.
#
# The player stub sleeps rather than returning, because a launch that exits at
# once is exactly what play_detached reads as a failure.
stub_player_chain() {
	local log=$1
	cat >"$STUB_BIN/yt-dlp" <<EOF
#!/usr/bin/env bash
printf 'YTDLP %s\n' "\$*" >>"$log"
EOF
	cat >"$STUB_BIN/mpv" <<EOF
#!/usr/bin/env bash
printf 'MPV %s\n' "\$*" >>"$log"
sleep 3
EOF
	chmod +x "$STUB_BIN/yt-dlp" "$STUB_BIN/mpv"
}

# The still frame: a curl that writes bytes wherever -o points, and a chafa
# that says it drew. Stubbed rather than real so no test reaches the network
# for a thumbnail.
stub_still() {
	local log=$1
	cat >"$STUB_BIN/curl" <<EOF
#!/usr/bin/env bash
printf 'CURL %s\n' "\$*" >>"$log"
while [ \$# -gt 0 ]; do
	if [ "\$1" = "-o" ]; then
		printf 'JPEGBYTES\n' >"\$2"
		shift
	fi
	shift
done
EOF
	cat >"$STUB_BIN/chafa" <<EOF
#!/usr/bin/env bash
printf 'CHAFA %s\n' "\$*" >>"$log"
printf 'STILL-FRAME\n'
EOF
	chmod +x "$STUB_BIN/curl" "$STUB_BIN/chafa"
}

# ctrl-o. Takes the results file, the focused index, then every marked index,
# which is what fzf's {1} and {+1} hand it.
run_action() {
	run env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" DDGX_TTL=0 \
		bash "$DDGX" --action "$@"
}

# One render of the preview pane, with the pane geometry fzf would export.
run_preview() {
	run env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" DDGX_TTL=0 \
		FZF_PREVIEW_COLUMNS=80 FZF_PREVIEW_LINES=24 \
		bash "$DDGX" --preview "$BATS_TEST_TMPDIR/results.json" "$1"
}

# A video result the extractor has already answered for: sidecar, extract and
# both stub chains in place.
write_playable_state() {
	local url="https://www.youtube.com/watch?v=aaa111"
	PLAYER_LOG="$BATS_TEST_TMPDIR/player.log"
	write_media_results
	seed_media "$url" "A conference talk" "https://i.ytimg.com/vi/aaa111/hq.jpg"
	seed_cache "$url" "the video's own metadata and transcript"
	stub_player_chain "$PLAYER_LOG"
	stub_still "$PLAYER_LOG"
}

@test "is_media_url recognises the hosts a player can open" {
	local url
	for url in \
		"https://www.youtube.com/watch?v=dQw4w9WgXcQ" \
		"https://m.youtube.com/watch?v=dQw4w9WgXcQ" \
		"https://www.youtube.com/shorts/abc123def" \
		"https://www.youtube.com/playlist?list=PLrAXtmRdnEQy6nuLMfO6uJhAP7CGYCzHk" \
		"https://youtu.be/dQw4w9WgXcQ" \
		"https://vimeo.com/76979871" \
		"https://vimeo.com/channels/staffpicks/76979871" \
		"https://www.twitch.tv/videos/1234567890" \
		"https://www.twitch.tv/clips/AwkwardHelplessSalamander" \
		"https://www.dailymotion.com/video/x8abcde" \
		"https://odysee.com/@channel:1/some-video:2" \
		"https://rumble.com/v1abcde-a-title.html"; do
		is_media "$url"
		if [ "$status" -ne 0 ]; then
			echo "expected a media url: $url" >&2
			return 1
		fi
	done
}

@test "is_media_url matches on host and path, never on a substring" {
	local url
	for url in \
		"https://kubernetes.io/docs/concepts/workloads/" \
		"https://www.youtube.com/feed/subscriptions" \
		"https://www.youtube.com/@somechannel" \
		"https://www.youtube.com/playlist" \
		"https://news.example.com/story?src=https://www.youtube.com/watch?v=abc" \
		"https://notyoutube.com/watch?v=abc" \
		"https://example.com/blog/youtu.be/why-i-hate-shorteners" \
		"https://vimeo.com/upgrade"; do
		is_media "$url"
		if [ "$status" -eq 0 ]; then
			echo "expected not a media url: $url" >&2
			return 1
		fi
	done
}

@test "ctrl-o on a video opens the player and says so in the header" {
	write_playable_state

	run_action "$BATS_TEST_TMPDIR/results.json" 0 0

	[ "$status" -eq 0 ]
	wait_for_line_matching "$PLAYER_LOG" '^MPV '

	# The player takes its own window and the picker stays up, so the only sign
	# the key did anything is the note. A detached launch is otherwise silent,
	# and a key that looks like it did nothing is a key you press again.
	[[ "$output" == "transform-header("* ]]
	run bash "$DDGX" --header "$BATS_TEST_TMPDIR/results.json"
	[[ "$output" == *"playing in mpv"* ]]
}

@test "ctrl-o on a page whose extract failed renders it in a browser" {
	printf '%s\n' '[{"title":"Blocked","url":"https://blocked.invalid/x","abstract":"nope"}]' \
		>"$BATS_TEST_TMPDIR/results.json"
	local args="$BATS_TEST_TMPDIR/node.args"
	cat >"$STUB_BIN/node" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$args"
printf 'the body only a browser could build\n'
EOF
	chmod +x "$STUB_BIN/node"

	run_action "$BATS_TEST_TMPDIR/results.json" 0 0

	# No cache entry is the same fact the red line in the pane is reporting: a
	# failed extract is never cached, and the preview ran it before you got
	# here. That is what picks the deep path for this row and no other.
	[ "$status" -eq 0 ]
	grep -q -- '--deep --url https://blocked.invalid/x --stats' "$args"
	[[ "$output" == "refresh-preview+transform-header("* ]]

	# The cache entry is replaced, not left at the extract that was too thin to
	# read, so the refreshed preview shows the render.
	local key
	key=$(printf '%s' "https://blocked.invalid/x" | sha1sum | cut -d' ' -f1)
	[ "$(cat "$CACHE_HOME/ddgx/$key.txt")" = "the body only a browser could build" ]

	run bash "$DDGX" --header "$BATS_TEST_TMPDIR/results.json"
	[[ "$output" == *"rendered the slow way"* ]]
}

@test "ctrl-o on anything else reads the marked set in a pager" {
	write_two_results

	run_action "$BATS_TEST_TMPDIR/results.json" 0 0 1

	# The behaviour ctrl-o always had, kept for every row that is neither a
	# video nor an unreadable page, and still over the marked set rather than
	# the focused row.
	[ "$status" -eq 0 ]
	[[ "$output" == "execute("*" --read "* ]]
	[[ "$output" == *"results.json 0 1)" ]]
}

@test "the sidecar decides what is playable, not the shape of the url" {
	# A url no pattern in this script would call media, which the extractor
	# resolved as a video anyway. The extractor asked yt-dlp, which is the tool
	# that has to play it, so its answer is the one that counts.
	printf '%s\n' '[{"title":"A talk","url":"https://media.example.org/talks/42","abstract":"a"}]' \
		>"$BATS_TEST_TMPDIR/results.json"
	local log="$BATS_TEST_TMPDIR/player.log"
	seed_media "https://media.example.org/talks/42" "A talk" ""
	seed_cache "https://media.example.org/talks/42" "the transcript"
	stub_player_chain "$log"

	run_action "$BATS_TEST_TMPDIR/results.json" 0 0

	# is_media_url would have called this a page and sent ctrl-o to the pager.
	[ "$status" -eq 0 ]
	wait_for_line_matching "$log" '^MPV '
	[[ "$output" == "transform-header("* ]]
	grep -q '^MPV https://media.example.org/talks/42$' "$log"
}

@test "the player is handed the page url, so it can reach native quality" {
	write_playable_state

	run_action "$BATS_TEST_TMPDIR/results.json" 0 0
	[ "$status" -eq 0 ]
	wait_for_line_matching "$PLAYER_LOG" '^MPV '

	# Pre-resolving with `yt-dlp --get-url` caps playback at 720p by
	# construction: it can only return a progressive format, and everything
	# above that exists on YouTube as separate DASH video and audio the player
	# merges itself. Given the page url, mpv applies the ytdl-format chain in
	# the user's own mpv.conf, which is where the preference belongs.
	grep -q '^MPV https://www.youtube.com/watch?v=aaa111$' "$PLAYER_LOG"
	! grep -q '^YTDLP ' "$PLAYER_LOG"
}

@test "the player takes its extra flags from DDGX_PLAYER_ARGS" {
	write_playable_state

	run env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" DDGX_TTL=0 \
		DDGX_PLAYER_ARGS='--fullscreen' \
		bash "$DDGX" --action "$BATS_TEST_TMPDIR/results.json" 0 0

	[ "$status" -eq 0 ]
	wait_for_line_matching "$PLAYER_LOG" '^MPV '
	grep -q '^MPV --fullscreen https://www.youtube.com/watch?v=aaa111$' "$PLAYER_LOG"
}

@test "a player that dies on the url says why in the header" {
	write_playable_state
	cat >"$STUB_BIN/mpv" <<'EOF'
#!/usr/bin/env bash
echo 'Failed to recognize file format.' >&2
exit 1
EOF
	chmod +x "$STUB_BIN/mpv"

	run_action "$BATS_TEST_TMPDIR/results.json" 0 0
	[ "$status" -eq 0 ]

	# The errors the old keys produced arrived stacked on top of the result
	# list, with nothing saying which result they were about or even that a
	# player had been involved. The player's output never reaches the terminal
	# now, so the note is the only place left for it to be reported, and a
	# launch that failed must not read as one that worked.
	run bash "$DDGX" --header "$BATS_TEST_TMPDIR/results.json"
	[[ "$output" == *"cannot play: Failed to recognize file format."* ]]
	[[ "$output" != *"playing in"* ]]
}

@test "a missing player is reported rather than silently doing nothing" {
	write_playable_state
	rm -f "$STUB_BIN/mpv"

	run env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" DDGX_TTL=0 \
		DDGX_PLAYER=not-a-real-player \
		bash "$DDGX" --action "$BATS_TEST_TMPDIR/results.json" 0 0

	[ "$status" -eq 0 ]
	run bash "$DDGX" --header "$BATS_TEST_TMPDIR/results.json"
	[[ "$output" == *"not-a-real-player not found"* ]]
}

@test "a media preview leads with the still frame, above the text" {
	write_playable_state

	run_preview 0
	[ "$status" -eq 0 ]

	# chafa's symbol output is plain text with colour, so the frame draws in the
	# pane with no image protocol from the terminal and no help from fzf.
	grep -q '^CHAFA .*--format symbols' "$PLAYER_LOG"

	local still_at text_at
	still_at=$(grep -n 'STILL-FRAME' <<<"$output" | head -1 | cut -d: -f1)
	text_at=$(grep -n 'metadata and transcript' <<<"$output" | head -1 | cut -d: -f1)
	[ -n "$still_at" ]
	[ -n "$text_at" ]
	[ "$still_at" -lt "$text_at" ]

	# Fetched once and kept. The preview command runs again on every keystroke
	# that moves the selection, and a thumbnail downloaded per keypress would
	# make the pane slower than the extract drawn under it.
	run_preview 0
	[ "$(grep -c '^CURL ' "$PLAYER_LOG")" -eq 1 ]
}

@test "an ordinary page gets no still frame and no player" {
	write_two_results
	local log="$BATS_TEST_TMPDIR/player.log"
	stub_player_chain "$log"
	stub_still "$log"

	run_preview 0

	[ "$status" -eq 0 ]
	[[ "$output" == *"body of the first page"* ]]
	[ ! -e "$log" ]
}

@test "the header carries the query, and a note only until it is read" {
	write_search_state 'kubernetes finalizers site:kubernetes.io'
	printf 'bookmarked to pet-links.toml\n' >"$RESULTS.note"

	run bash "$DDGX" --header "$RESULTS"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == "query: kubernetes finalizers site:kubernetes.io"* ]]
	[[ "${lines[0]}" == *"bookmarked to pet-links.toml"* ]]
	[[ "${lines[1]}" == *"ctrl-o play, render or read"* ]]
	[[ "${lines[2]}" == *"alt-q refine"* ]]

	# What just happened is not part of the query: it goes once it is shown.
	run bash "$DDGX" --header "$RESULTS"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" != *"bookmarked"* ]]
}

@test "no picker key is one tmux's root table answers first" {
	# A key bound in tmux's root table is intercepted before the pane's program
	# is offered it, so fzf never sees it. ddgx always runs inside tmux, through
	# the M-g popup, which makes any overlap a key that silently does nothing
	# while the header advertises it. ctrl-\ was exactly that for as long as it
	# was in the key list.
	#
	# The evidence has to be the config. `tmux send-keys` injects straight into
	# the pane and bypasses the root table, so a send-keys probe shows only that
	# fzf handles a key, never that the key would arrive in real use, and it
	# will tell you an intercepted key is fine.
	local conf="$REPO_ROOT/.tmux.conf"
	[ -f "$conf" ] || skip "no .tmux.conf in this repo"

	local claimed bound key tmux_key
	# The trailing quote-or-space matters: without it C-PageDown reads as C-P
	# and C-M-r as C-M, and the guard starts failing keys tmux never claimed.
	claimed=$(grep -oE "^bind(-key)? +-n +'?C-[A-Za-z\\\\]('| )" "$conf" |
		sed "s/.*C-/C-/; s/['[:space:]]*$//" | sort -u)
	bound=$(grep -oE -- "--bind=['\"]?ctrl-[a-z\\\\]" "$DDGX" |
		sed 's/.*ctrl-/ctrl-/' | sort -u)

	# Both sides must actually have matched something, or this passes by
	# finding nothing and proves nothing.
	[ -n "$claimed" ]
	[ -n "$bound" ]

	for key in $bound; do
		tmux_key="C-${key#ctrl-}"
		if grep -qxF "$tmux_key" <<<"$claimed"; then
			echo "picker binds $key, but .tmux.conf claims $tmux_key at the root" >&2
			return 1
		fi
	done
}

@test "every header line survives the width fzf gives the header" {
	write_search_state 'kubernetes finalizers'

	run bash "$DDGX" --header "$RESULTS"

	# fzf hands the header the width of the result list, not of the terminal,
	# so at the default 58% preview a line is cut around 98 columns and
	# everything past the cut is simply gone. A key you cannot see does not
	# exist, which is what made this worth a test rather than a careful eye.
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 3 ]
	local line
	for line in "${lines[@]}"; do
		[ "$(wc -L <<<"$line")" -le 98 ]
	done
}

# --------------------------------------------------------------------------
# The media branch
#
# extract() enters it only when html is null, so these drive __readable.mjs
# with --url and no --file. That is also what un-gates the page path's fetch,
# so every test here sets DDGX_NO_NETWORK: an unstubbed request must fail
# loudly rather than reach YouTube and flake on a rate limit six months from
# now.
# --------------------------------------------------------------------------

# yt-dlp answers --dump-single-json on stdout and nothing else is read, so a
# stub is one heredoc. Exit 0, because the caller treats any other code as a
# failed lookup.
stub_ytdlp() {
	cat >"$STUB_BIN/yt-dlp" <<EOF
#!/usr/bin/env bash
cat <<'JSON'
$1
JSON
EOF
	chmod +x "$STUB_BIN/yt-dlp"
}

# The other half of the contract: a yt-dlp that fails the way a marketing page
# on a video host makes it fail.
stub_ytdlp_failing() {
	cat >"$STUB_BIN/yt-dlp" <<'EOF'
#!/usr/bin/env bash
echo 'ERROR: Unsupported URL' >&2
exit 1
EOF
	chmod +x "$STUB_BIN/yt-dlp"
}

run_media() {
	run env PATH="$STUB_BIN:$PATH" DDGX_NO_NETWORK=1 \
		node "$READABLE" --url "$1" "${@:2}"
}

# A flat channel listing: what yt-dlp returns for /@handle with
# --flat-playlist. No playlist_count, which is what a channel actually omits.
channel_json() {
	cat <<'JSON'
{
  "title": "Some Channel",
  "channel": "Some Channel",
  "webpage_url": "https://www.youtube.com/@somechannel/videos",
  "entries": [
    { "title": "First upload", "duration": 615 },
    { "title": "Second upload", "duration": 3725 },
    null
  ]
}
JSON
}

@test "media: the no-network tripwire actually stops a fetch" {
	# Guards every other test in this block: if the tripwire silently did
	# nothing, the fallback test below would pass for the wrong reason.
	run env DDGX_NO_NETWORK=1 node "$READABLE" --url https://example.com/post

	[ "$status" -eq 1 ]
	[[ "$output" == *"network disabled"* ]]
}

@test "media: a channel renders its video list, not the cookie banner" {
	stub_ytdlp "$(channel_json)"

	run_media 'https://www.youtube.com/@somechannel'

	[ "$status" -eq 0 ]
	[[ "$output" == *"Some Channel"* ]]
	[[ "$output" == *"1. First upload (10:15)"* ]]
	[[ "$output" == *"2. Second upload (1:02:05)"* ]]
	# The null entry is filtered, so it must not become a third line.
	[[ "$output" != *"3. "* ]]
}

@test "media: a channel writes no sidecar, so the picker never offers to play it" {
	stub_ytdlp "$(channel_json)"
	local cache="$BATS_TEST_TMPDIR/mediacache"

	run_media 'https://www.youtube.com/@somechannel' --cache "$cache"

	[ "$status" -eq 0 ]
	# Playing a channel means queueing every upload it has. The absence of the
	# record is the whole mechanism that prevents it.
	[ -z "$(find "$cache" -name '*.media' 2>/dev/null)" ]
}

@test "media: a playlist does write a sidecar" {
	# The contrast that stops the channel assertion above being vacuous: same
	# code path, same renderer, and the sidecar turns on.
	stub_ytdlp '{
	  "title": "Some Playlist",
	  "playlist_count": 2,
	  "webpage_url": "https://www.youtube.com/playlist?list=PL1",
	  "entries": [
	    { "title": "First", "duration": 60,
	      "thumbnails": [ { "url": "https://i.ytimg.com/vi/a/hq.jpg", "width": 480 } ] }
	  ]
	}'
	local cache="$BATS_TEST_TMPDIR/mediacache"

	run_media 'https://www.youtube.com/playlist?list=PL1' --cache "$cache"

	[ "$status" -eq 0 ]
	local sidecar
	sidecar=$(find "$cache" -name '*.media')
	[ -n "$sidecar" ]
	[[ "$(cat "$sidecar")" == *'"kind":"playlist"'* ]]
}

@test "media: a channel url reaches yt-dlp as the /videos listing" {
	# channelListingUrl rewrites /@handle to /@handle/videos. Without it yt-dlp
	# is handed the channel home, which is a different extraction.
	cat >"$STUB_BIN/yt-dlp" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >"$BATS_TEST_TMPDIR/ytdlp-args"
echo '{"title":"x","entries":[]}'
EOF
	chmod +x "$STUB_BIN/yt-dlp"

	run_media 'https://www.youtube.com/@somechannel'

	[[ "$(cat "$BATS_TEST_TMPDIR/ytdlp-args")" == *"https://www.youtube.com/@somechannel/videos"* ]]
	[[ "$(cat "$BATS_TEST_TMPDIR/ytdlp-args")" == *"--flat-playlist"* ]]
}

@test "media: a failed lookup falls through to the page path" {
	# vimeo.com/features is marketing, not a video, and no path pattern
	# separates the two. The fallback is what stopped it reporting yt-dlp's
	# 404 instead of the page. Here the page half is refused by the tripwire,
	# so what is under test is the routing and the error precedence at the end
	# of extract(): the reason reported must be yt-dlp's, never the fetch's.
	stub_ytdlp_failing

	run_media 'https://vimeo.com/features'

	[ "$status" -eq 1 ]
	# yt-dlp's own reason, carried out through mediaError with the ERROR:
	# prefix stripped by toolError. Its presence proves the media branch ran
	# and lost; its survival past the page attempt proves the precedence.
	[[ "$output" == *"Unsupported URL"* ]]
	# The page path was reached (that is the fallback) and it failed too, so
	# the losing error is the network one. It must not be what gets reported:
	# "no article found" or a fetch failure would send a reader hunting for a
	# renderer, which is never what is wrong here.
	[[ "$output" != *"network disabled"* ]]
}

# Build a flat listing of N entries, the shape --flat-playlist returns.
listing_json() {
	local count=$1 total=$2 entries="" i
	for ((i = 1; i <= count; i++)); do
		[ -n "$entries" ] && entries="$entries,"
		entries="$entries{\"title\":\"Video $i\",\"duration\":60}"
	done
	if [ "$total" = "null" ]; then
		printf '{"title":"L","playlist_count":null,"entries":[%s]}' "$entries"
	else
		printf '{"title":"L","playlist_count":%s,"entries":[%s]}' "$total" "$entries"
	fi
}

@test "media: a playlist cut by the cap says how much it dropped" {
	# LISTING_MAX is 40 and yt-dlp still reports the real length alongside it,
	# so the header saying 917 above a list of 40 is a disagreement the reader
	# should not have to spot.
	stub_ytdlp "$(listing_json 40 917)"

	run_media 'https://www.youtube.com/playlist?list=PL1'

	[ "$status" -eq 0 ]
	[[ "$output" == *"917 videos"* ]]
	[[ "$output" == *"[showing 40 of 917]"* ]]
}

@test "media: a channel at the cap says so without inventing a total" {
	# A channel reports playlist_count null, so there is no honest number to
	# put after "of". It can only name what it is showing.
	stub_ytdlp "$(listing_json 40 null)"

	run_media 'https://www.youtube.com/@somechannel'

	[ "$status" -eq 0 ]
	[[ "$output" == *"[showing the first 40, no total reported]"* ]]
	[[ "$output" != *" of "* ]]
}

@test "media: a complete list says nothing about truncation" {
	# Over-warning on a list that dropped nothing teaches the reader to skip
	# the line, which costs the warning its whole value.
	stub_ytdlp "$(listing_json 3 3)"

	run_media 'https://www.youtube.com/playlist?list=PL1'

	[ "$status" -eq 0 ]
	[[ "$output" == *"3 videos"* ]]
	[[ "$output" != *"showing"* ]]
}

# --------------------------------------------------------------------------
# The hand-off. alt-h gives the marked results' note PATHS to the pane the M-g
# popup was opened from, through deliver_to_pane in __lib_pane_deliver.sh.
#
# The pane is resolved once, when the search starts, into "<results>.target",
# so these tests write that file rather than the global tmux option: reading the
# option at send time is the bug the sidecar exists to prevent.
#
# Most of it runs against a stubbed tmux, because the thing worth locking is the
# exact command line, and only a stub can be asked what it was handed. The one
# test that needs a real pane starts a server of its own on a private socket.
# --------------------------------------------------------------------------

# Stub tmux so a delivery can be read back verbatim. Every call is appended to
# a log, load-buffer's stdin is kept as the payload, and a pane counts as live
# only when its id was named here. An unknown pane is answered the way tmux
# answers one: nothing on stdout, exit 0. That is the whole reason pane_is_live
# tests the output instead of the status, so the stub must not make it easier.
stub_tmux() {
	TMUX_LOG="$BATS_TEST_TMPDIR/tmux.log"
	TMUX_BUFFER="$BATS_TEST_TMPDIR/tmux.buffer"
	rm -f "$TMUX_LOG" "$TMUX_BUFFER"
	printf '%s\n' "$@" >"$STUB_BIN/tmux.live"
	cat >"$STUB_BIN/tmux" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TMUX_LOG"
case "\$1" in
display-message)
	fmt="\${*: -1}"
	pane=""
	while [ \$# -gt 0 ]; do
		[ "\$1" = "-t" ] && pane="\$2"
		shift
	done
	[ -n "\$pane" ] || exit 0
	grep -qxF "\$pane" "$STUB_BIN/tmux.live" 2>/dev/null || exit 0
	case "\$fmt" in
	*session_name*) printf 'search:0.1\n' ;;
	*) printf '%s\n' "\$pane" ;;
	esac
	;;
load-buffer)
	cat >"$TMUX_BUFFER"
	;;
esac
exit 0
EOF
	chmod +x "$STUB_BIN/tmux"
}

# The results file every hand-off test sends from, with the pane the popup was
# opened from already pinned beside it.
write_send_state() {
	SEND_RESULTS="$BATS_TEST_TMPDIR/results.json"
	write_two_results
	printf '%s' "${1:-}" >"$(printf '%s.target' "$SEND_RESULTS")"
}

run_send() {
	run env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" \
		XDG_DATA_HOME="$DATA_HOME" DDGX_TTL=0 bash "$DDGX" --send "$@"
}

# What the picker would show after the key: the note, consumed on read.
send_header() {
	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --header "$SEND_RESULTS"
}

@test "the picker binds alt-h to the hand-off" {
	# fzf cannot be driven far enough here to press a key, so the binding is
	# read from the source. A key advertised in the header and bound nowhere is
	# a key that silently does nothing, which is the failure this file already
	# guards for ctrl-\.
	local bind
	bind=$(grep -F -- '--bind="alt-h:' "$DDGX")

	[ -n "$bind" ]
	[[ "$bind" == *"--send"* ]]
	# The marked set, {+1}, not the focused row, {1}: marking five results and
	# handing over one is the silent half-delivery.
	[[ "$bind" == *"{+1}"* ]]
	# execute-silent keeps the picker drawn, and the header transform after it
	# is the only channel mode_send's outcome has back to the screen.
	[[ "$bind" == *"execute-silent"* ]]
	[[ "$bind" == *"transform-header"* ]]

	write_send_state '%7'
	send_header
	[[ "$output" == *"alt-h"* ]]
}

@test "the hand-off gives up the same notes ctrl-e opens" {
	write_send_state '%7'
	printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/opened.txt"\n' \
		"$BATS_TEST_TMPDIR" >"$STUB_BIN/fake-editor"
	chmod +x "$STUB_BIN/fake-editor"

	run env XDG_CACHE_HOME="$CACHE_HOME" XDG_DATA_HOME="$DATA_HOME" DDGX_TTL=0 \
		DDGX_EDITOR="$STUB_BIN/fake-editor" \
		bash "$DDGX" --edit "$SEND_RESULTS" 0 1
	[ "$status" -eq 0 ]

	stub_tmux '%7'
	run_send "$SEND_RESULTS" 0 1
	[ "$status" -eq 0 ]

	# Both keys go through note_paths, so a path you were handed is the file
	# ctrl-e would have opened. Two naming rules that agree today drift the
	# first time either slug is touched, and then the two keys disagree about
	# what "this result" means.
	[ -s "$TMUX_BUFFER" ]
	[ "$(cat "$TMUX_BUFFER")" = "$(cat "$BATS_TEST_TMPDIR/opened.txt")" ]
	[ "$(grep -c '/ddgx/notes/' "$TMUX_BUFFER")" -eq 2 ]
}

@test "the hand-off gives up the note path, never the page text" {
	write_send_state '%7'
	stub_tmux '%7'

	run_send "$SEND_RESULTS" 0

	# The agent in that pane reads the file itself, at full fidelity. Pasting
	# the markdown would put kilobytes on an input line, unreviewable before it
	# is sent and lossy at the edges.
	# A negated assertion is written as a [[ ]] comparison throughout this
	# block, never as `! grep`: bash exempts a command whose status is inverted
	# with ! from set -e, so `! grep -q` under bats passes whether or not the
	# pattern is there. Measured on a mutant that pasted the text.
	[ "$status" -eq 0 ]
	[ "$(cat "$TMUX_BUFFER")" = "$DATA_HOME/ddgx/notes/first-hit.md" ]
	[[ "$(cat "$TMUX_BUFFER")" != *"body of the first page"* ]]
	# The text is not missing, it is where it belongs: in the file whose path
	# just went over.
	grep -q 'body of the first page' "$DATA_HOME/ddgx/notes/first-hit.md"

	send_header
	[[ "$output" == *"handed 1 extract(s) to search:0.1"* ]]
}

@test "a hand-off into a pane that is gone says so rather than failing quietly" {
	write_send_state '%999'
	stub_tmux '%7'

	run_send "$SEND_RESULTS" 0

	# display-message answers an unknown pane with an empty line and exit 0, so
	# a check that branched on the status would call the pane live, the paste
	# would fail inside a backgrounded run-shell where nobody sees it, and the
	# payload would be lost with no error at all.
	[ "$status" -eq 0 ]
	[ ! -e "$TMUX_BUFFER" ]
	send_header
	[[ "$output" == *"pane %999 is gone, nothing handed off"* ]]
	[[ "$output" != *"handed 1 extract"* ]]
}

@test "a hand-off with no source pane recorded names that as the reason" {
	write_send_state ''
	stub_tmux '%7'

	run_send "$SEND_RESULTS" 0

	# Two failures with one symptom. Running ddgx outside the M-g popup leaves
	# nothing to deliver into, and reporting that as a dead pane sends you
	# hunting for a pane that was never named.
	[ "$status" -eq 0 ]
	[ ! -e "$TMUX_BUFFER" ]
	send_header
	[[ "$output" == *"no source pane"* ]]
	[[ "$output" != *"is gone"* ]]
}

@test "a hand-off of an index past the end delivers nothing" {
	write_send_state '%7'
	stub_tmux '%7'

	run_send "$SEND_RESULTS" 99

	[ "$status" -eq 0 ]
	send_header
	[[ "$output" == *"nothing to hand off"* ]]
	# Not one tmux call, so there is no buffer to leak and no empty paste to
	# land on the input line of a pane that was minding its own business.
	[ ! -e "$TMUX_LOG" ]
	# And no note scaffolded for a result that does not exist: the notes
	# directory is durable, so junk written there stays.
	[ -z "$(ls -A "$DATA_HOME/ddgx/notes" 2>/dev/null)" ]
}

@test "the hand-off pastes with -p, so a multi-line payload cannot execute" {
	write_send_state '%7'
	stub_tmux '%7'

	run_send "$SEND_RESULTS" 0 1
	[ "$status" -eq 0 ]

	# paste-buffer without -p replays the buffer as keystrokes and every newline
	# is an Enter, so a two-path hand-off ran the first path as a command. -p
	# wraps the paste in bracketed-paste markers, which readline and every
	# terminal UI treat as literal text.
	local paste load buffer
	paste=$(grep -F 'paste-buffer' "$TMUX_LOG")
	[ -n "$paste" ]
	[[ "$paste" == *"paste-buffer -p "* ]]

	# Two paths, so the flag is load-bearing in this very payload rather than
	# in some other test's.
	[ "$(grep -c '/ddgx/notes/' "$TMUX_BUFFER")" -eq 2 ]

	# The paste must name the buffer that was just loaded, or -p is protecting
	# somebody else's bytes.
	load=$(grep -F 'load-buffer' "$TMUX_LOG")
	buffer=$(sed -n 's/.*load-buffer -b \([^ ]*\).*/\1/p' <<<"$load")
	[ -n "$buffer" ]
	[[ "$paste" == *"-b '$buffer'"* ]]

	# Deferred past the popup's teardown: the popup owns the client until its
	# process exits, and a paste issued from inside it races the handover and
	# lands in a pane still being torn down.
	[[ "$paste" == "run-shell -b "* ]]
}

@test "the hand-off submits nothing" {
	write_send_state '%7'
	stub_tmux '%7'

	run_send "$SEND_RESULTS" 0 1
	[ "$status" -eq 0 ]

	# The paths land on the input line and the human types what they want done
	# with them. A popup that submits on your behalf submits the wrong thing
	# into a live agent, and there is no undo for that.
	local log
	log=$(cat "$TMUX_LOG")
	[[ "$log" != *"send-keys"* ]]
	[[ "$log" != *"Enter"* ]]
	[[ "$log" != *"C-m"* ]]
	# No trailing newline either: a payload that ends in one is a submit the
	# moment anything replays it as keystrokes.
	[ -n "$(tail -c1 "$TMUX_BUFFER")" ]
}

# A tmux server of this test's own, on a socket directory it created. TMUX is
# unset for every call because a set TMUX names a socket outright and beats
# TMUX_TMPDIR: inherited from the tmux the suite is being run from, it would aim
# a paste at one of the reader's own panes. Probed, not assumed.
private_tmux() {
	env -u TMUX TMUX_TMPDIR="$TMUX_SOCKET_DIR" tmux -f /dev/null "$@"
}

# Only ever tears down a server this file started. Without the guard a bare
# kill-server would reach the default socket, which is where the reader is.
teardown() {
	[ -n "${TMUX_SOCKET_DIR:-}" ] || return 0
	private_tmux kill-server 2>/dev/null || true
	rm -rf "$TMUX_SOCKET_DIR"
}

@test "a hand-off into a live pane lands on its input line, unsubmitted" {
	command -v tmux >/dev/null 2>&1 || skip "tmux not installed"
	write_send_state ''

	# Under /tmp, not the test tmpdir: the socket path is a sockaddr_un and a
	# long enough prefix makes the connect fail with "File name too long".
	TMUX_SOCKET_DIR=$(mktemp -d /tmp/ddgx-bats-XXXXXX)
	private_tmux new-session -d -s ddgx-handoff -x 240 -y 20 'bash --norc -i'

	local i ready=0
	for ((i = 0; i < 60; i++)); do
		if private_tmux capture-pane -p -t ddgx-handoff | grep -q '^bash-'; then
			ready=1
			break
		fi
		sleep 0.1
	done
	[ "$ready" -eq 1 ]

	local pane
	pane=$(private_tmux list-panes -t ddgx-handoff -F '#{pane_id}' | head -1)
	printf '%s' "$pane" >"$SEND_RESULTS.target"

	run env -u TMUX TMUX_TMPDIR="$TMUX_SOCKET_DIR" \
		XDG_CACHE_HOME="$CACHE_HOME" XDG_DATA_HOME="$DATA_HOME" DDGX_TTL=0 \
		bash "$DDGX" --send "$SEND_RESULTS" 0 1
	[ "$status" -eq 0 ]

	# The paste is deferred by run-shell -b, so wait for it rather than racing.
	local cap
	for ((i = 0; i < 60; i++)); do
		cap=$(private_tmux capture-pane -p -t "$pane")
		[[ "$cap" == *"second-hit.md"* ]] && break
		sleep 0.1
	done

	# Both paths sit on one input line, unrun. Without -p this pane shows the
	# first path echoed as a command, "Permission denied" under it, and a second
	# prompt: the shell executed the line the newline terminated. Measured, on
	# this tmux and this bash, before the assertion was written.
	[[ "$cap" == *"$DATA_HOME/ddgx/notes/first-hit.md"* ]]
	[[ "$cap" == *"$DATA_HOME/ddgx/notes/second-hit.md"* ]]
	[[ "$cap" != *"Permission denied"* ]]
	[[ "$cap" != *"command not found"* ]]
	[ "$(grep -c '^bash-' <<<"$cap")" -eq 1 ]
	# The page text stayed in the file, as it does with the stub.
	[[ "$cap" != *"body of the first page"* ]]
}
