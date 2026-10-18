#!/usr/bin/env bats
#
# Covers the search hybrid: __readable.mjs (Mozilla Readability + Turndown)
# and __ddgx.sh's result rendering. No test fetches over the network: the
# extractor is fed local fixtures, ddgr is stubbed, and the dump/preview modes
# read a pre-seeded cache. The pdf and rescue tests serve their fixtures from
# a loopback server, because --file skips the fetch they start from.

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
	# The default path renders a thin page on the cluster, so a test that does
	# not point this at a config of its own would reach the real renderer.
	export DDGX_C4AI_CONFIG="$BATS_TEST_TMPDIR/absent-crawl4ai.json"
	# alt-v calls the YouTube API by default. A test that does not stub it must
	# fail to fetch, never spend the real quota.
	export DDGX_VIDEOS_CMD="$BATS_TEST_TMPDIR/no-videos-cmd"
	export DDGX_YOUTUBE_CONFIG="$BATS_TEST_TMPDIR/absent-youtube.json"

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
# the deep ladder
#
# Every rung below the first is a subprocess reached by bare name, which is
# what makes the ladder testable at all: curl, google-chrome and w3m are all
# stubbed on PATH here. The url is under .invalid, so the fetch these tests
# escalate from fails in the resolver on this machine rather than by asking
# the internet, and DDGX_NO_NETWORK cannot stand in for it: that guard is the
# thing two of these tests are about.
# --------------------------------------------------------------------------

DEEP_URL=https://blocked.invalid/x

# Comfortably past DEEP_MIN, so a rung that answers with this counts as having
# read the page rather than as one more thin result. Land under that floor and
# the ladder keeps climbing, which is correct behaviour and a confusing test.
cluster_markdown() {
	printf 'The cluster renderer reached this page and read it. '
	printf 'It is long enough to count as a page that read, which is the only '
	printf 'thing separating a rung that worked from a rung that returned a '
	printf 'navigation bar, and the ladder judges every rung by that one '
	printf 'measure rather than by which tool produced it. These sentences '
	printf 'exist to carry the character count past the floor with enough '
	printf 'margin that nobody has to count them again after an edit, because '
	printf 'a fixture that sits one word above a threshold is a test that '
	printf 'fails for a reason nothing in it names.\n'
}

# curl answering the way crawl4ai's /crawl does, with the body it would return.
# The response is built once and read back by the stub, so the markdown is
# escaped by a json encoder rather than by a heredoc inside a heredoc. The
# markdown it carries is cluster_markdown's unless a test passes its own.
stub_curl_ok() {
	{ if [ $# -gt 0 ]; then printf '%s\n' "$1"; else cluster_markdown; fi; } | python3 -c \
		'import json,sys; md=sys.stdin.read(); print(json.dumps({"success": True, "results": [{"success": True, "markdown": {"raw_markdown": md, "fit_markdown": md}}]}))' \
		>"$BATS_TEST_TMPDIR/curl.response"
	cat >"$STUB_BIN/curl" <<EOF
#!/usr/bin/env bash
cat >"$BATS_TEST_TMPDIR/curl.stdin"
printf '%s\n' "\$*" >>"$BATS_TEST_TMPDIR/curl.args"
cat "$BATS_TEST_TMPDIR/curl.response"
EOF
	chmod +x "$STUB_BIN/curl"
}

# curl's exit code carries the distinction the breaker turns on: 22 is the
# service answering with an HTTP error, 7 is nothing listening at all.
stub_curl_failing() {
	cat >"$STUB_BIN/curl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$BATS_TEST_TMPDIR/curl.args"
exit $1
EOF
	chmod +x "$STUB_BIN/curl"
}

stub_chrome() {
	cat >"$STUB_BIN/google-chrome" <<EOF
#!/usr/bin/env bash
printf 'started\n' >>"$BATS_TEST_TMPDIR/chrome.log"
cat "$FIXTURES/article.html"
EOF
	chmod +x "$STUB_BIN/google-chrome"
}

write_c4ai_config() {
	printf '{"url":"https://renderer.invalid/md","auth":"Bearer %s","ca":"/dev/null"}\n' \
		"secret-token-value" >"$BATS_TEST_TMPDIR/crawl4ai.json"
}

run_deep() {
	run env PATH="$STUB_BIN:$PATH" TMPDIR="$BATS_TEST_TMPDIR" \
		DDGX_C4AI_CONFIG="$BATS_TEST_TMPDIR/crawl4ai.json" \
		node "$READABLE" --deep --url "$DEEP_URL" "$@"
}

@test "the cluster renderer answers first and the browser is never started" {
	write_article_fixture
	write_c4ai_config
	stub_curl_ok
	stub_chrome

	run_deep

	[ "$status" -eq 0 ]
	[[ "$output" == *"The cluster renderer reached this page"* ]]
	[[ "$output" == *"[step 2: crawl4ai fit filter over the cluster renderer]"* ]]
	# The rung with no local process beat the one that starts a browser, so
	# the expensive one never ran. This is the whole reason it goes first.
	[ ! -f "$BATS_TEST_TMPDIR/chrome.log" ]
}

@test "the token travels on stdin, never in the argument list" {
	write_article_fixture
	write_c4ai_config
	stub_curl_ok
	# Stubbed even though this rung should win, because the machine running
	# the suite has a real Chrome and a rung that falls through would find it.
	stub_chrome

	run_deep

	[ "$status" -eq 0 ]
	# /proc/PID/cmdline is world readable and an argv full of bearer token is
	# a credential handed to every process on the machine.
	run grep -c secret-token-value "$BATS_TEST_TMPDIR/curl.args"
	[ "$output" = "0" ]
	grep -q secret-token-value "$BATS_TEST_TMPDIR/curl.stdin"
	grep -q -- '--config -' "$BATS_TEST_TMPDIR/curl.args"
}

@test "a page the cluster renderer refuses falls through to the browser" {
	write_article_fixture
	write_c4ai_config
	stub_curl_failing 22
	stub_chrome

	run_deep

	[ "$status" -eq 0 ]
	[[ "$output" == *"Cordoning a node marks it unschedulable"* ]]
	[[ "$output" == *"[deep step 3: Readability over a headless Chrome render]"* ]]
	# The service answered, so it is up. Remembering it as down would skip it
	# for every other page for a minute over one page it did not like.
	[ ! -f "$BATS_TEST_TMPDIR/ddgx-crawl4ai-unreachable" ]
}

@test "an unreachable cluster is remembered, so the next page does not wait for it" {
	write_article_fixture
	write_c4ai_config
	stub_curl_failing 7
	stub_chrome

	run_deep
	[ "$status" -eq 0 ]
	[[ "$output" == *"[deep step 3: Readability over a headless Chrome render]"* ]]
	[ -f "$BATS_TEST_TMPDIR/ddgx-crawl4ai-unreachable" ]

	run_deep
	[ "$status" -eq 0 ]
	[[ "$output" == *"[deep step 3: Readability over a headless Chrome render]"* ]]

	# Once. A tunnel is down for stretches, not for single requests, and the
	# day it is down is already the day this key is slowest.
	[ "$(wc -l <"$BATS_TEST_TMPDIR/curl.args")" -eq 1 ]
}

@test "the rung is skipped on a machine with no renderer configured" {
	write_article_fixture
	stub_curl_ok
	stub_chrome

	run env PATH="$STUB_BIN:$PATH" TMPDIR="$BATS_TEST_TMPDIR" \
		DDGX_C4AI_CONFIG="$BATS_TEST_TMPDIR/absent.json" \
		node "$READABLE" --deep --url "$DEEP_URL"

	[ "$status" -eq 0 ]
	[[ "$output" == *"[deep step 3: Readability over a headless Chrome render]"* ]]
	[ ! -f "$BATS_TEST_TMPDIR/curl.args" ]
}

@test "a fetch the page refuses still reaches the ladder" {
	write_article_fixture
	stub_chrome

	run env PATH="$STUB_BIN:$PATH" TMPDIR="$BATS_TEST_TMPDIR" \
		DDGX_C4AI_CONFIG="$BATS_TEST_TMPDIR/absent.json" \
		node "$READABLE" --deep --url "$DEEP_URL"

	# The fetch failed and the page still read. Aborting on that failure is
	# what kept --deep from reaching a renderer on every page that answers a
	# script with 403, which is most of what the escalation is asked for.
	[ "$status" -eq 0 ]
	[[ "$output" == *"Cordoning a node marks it unschedulable"* ]]
}

@test "the shallow path still fails on a fetch the page refuses" {
	write_article_fixture
	stub_chrome

	run env PATH="$STUB_BIN:$PATH" node "$READABLE" --url "$DEEP_URL"

	# Nothing to fall to, so the reason travels to the pane instead, and the
	# browser stays unstarted: it is the escalation, not the default.
	[ "$status" -ne 0 ]
	[ ! -f "$BATS_TEST_TMPDIR/chrome.log" ]
}

@test "the network guard stops a deep extract at the fetch" {
	write_article_fixture
	write_c4ai_config
	stub_curl_ok
	stub_chrome

	run env PATH="$STUB_BIN:$PATH" TMPDIR="$BATS_TEST_TMPDIR" \
		DDGX_C4AI_CONFIG="$BATS_TEST_TMPDIR/crawl4ai.json" DDGX_NO_NETWORK=1 \
		node "$READABLE" --deep --url "$DEEP_URL"

	# Every rung under the first is a subprocess, and the guard cannot see
	# those. If --deep swallowed this refusal the way it swallows a 403, a
	# suite that stubs one binary would reach the internet through another.
	[ "$status" -ne 0 ]
	[[ "$output" == *"network disabled"* ]]
	[ ! -f "$BATS_TEST_TMPDIR/chrome.log" ]
	[ ! -f "$BATS_TEST_TMPDIR/curl.args" ]
}

# --------------------------------------------------------------------------
# alt-v, your own channel
#
# The listing script is stubbed: it prints the json __get_youtube_videos.py
# --json --comments would, and counts how often it was asked.
# --------------------------------------------------------------------------

write_videos_json() {
	cat >"$BATS_TEST_TMPDIR/videos.json" <<'JSON'
[{"id":"7D1k1l-Q8rA","url":"https://www.youtube.com/watch?v=7D1k1l-Q8rA","title":"10 Built-in Neovim Features","views":16393,"likes":719,"comment_count":34,"published_at":"2026-01-04","duration":1292,"short":false,"description":"Shell filters and multicursor, all built in.","comments":[{"author":"@Patterner","likes":6,"text":"still magical<br>to me <a href=\"https://x\">link</a>","replies":[{"author":"@piotr1215","likes":1,"text":"glad it helped"}]}]},
 {"id":"shortid0001","url":"https://www.youtube.com/watch?v=shortid0001","title":"One tmux trick","views":812,"likes":40,"comment_count":0,"published_at":"2025-11-02","duration":45,"short":true,"description":"","comments":[]}]
JSON
}

stub_videos_cmd() {
	cat >"$STUB_BIN/videos-cmd" <<EOF
#!/usr/bin/env bash
count=0
[ ! -s "$BATS_TEST_TMPDIR/videos.count" ] || count=\$(cat "$BATS_TEST_TMPDIR/videos.count")
printf '%s\n' "\$((count + 1))" >"$BATS_TEST_TMPDIR/videos.count"
printf '%s\n' "\$*" >"$BATS_TEST_TMPDIR/videos.args"
printf '%s %s\n' "\${YOUTUBE_API_KEY:-}" "\${YOUTUBE_CHANNEL_ID:-}" >"$BATS_TEST_TMPDIR/videos.env"
cat "$BATS_TEST_TMPDIR/videos.json"
EOF
	chmod +x "$STUB_BIN/videos-cmd"
}

run_videos() {
	run env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" \
		DDGX_VIDEOS_CMD="$STUB_BIN/videos-cmd" \
		YOUTUBE_API_KEY=test-key YOUTUBE_CHANNEL_ID=UCtest "$@" \
		bash "$DDGX" --videos "$BATS_TEST_TMPDIR/results.json"
}

@test "alt-v lists the channel newest first with the stats on the row" {
	write_two_results
	write_videos_json
	stub_videos_cmd

	run_videos

	[ "$status" -eq 0 ]
	R="$BATS_TEST_TMPDIR/results.json"
	[ "$(jq -r '.[0].title' "$R")" = '10 Built-in Neovim Features' ]
	[ "$(jq -r '.[0].abstract' "$R")" = '16,393 views · 719 likes · 34 comments · 2026-01-04' ]
	[ "$(jq -r '.[1].abstract' "$R")" = '812 views · 40 likes · 0 comments · 2025-11-02 · short' ]
	[ "$(cat "$R.engine")" = videos ]
	[ "$(cat "$R.typing")" = pages ]
	[ "$(cat "$BATS_TEST_TMPDIR/videos.args")" = '--json --comments' ]
	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --header "$R"
	[[ "${lines[0]}" == 'videos: your channel'* ]]
}

@test "a video's preview carries its stats and comments, and is playable" {
	write_two_results
	write_videos_json
	stub_videos_cmd
	run_videos
	# The thumbnail is the one thing the preview would fetch.
	stub_curl_failing 7

	run env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" FZF_PREVIEW_COLUMNS=80 \
		bash "$DDGX" --preview "$BATS_TEST_TMPDIR/results.json" 0 '' </dev/null

	[ "$status" -eq 0 ]
	[[ "$output" == *"(ctrl-o opens it in the player)"* ]]
	[[ "$output" == *"21:32"* ]]
	[[ "$output" == *"Shell filters and multicursor"* ]]
	# Display html flattened to text: a <br> is a space and a link its words.
	[[ "$output" == *"@Patterner (6 likes): still magical to me link"* ]]
	[[ "$output" == *"@piotr1215: glad it helped"* ]]
	sidecar=$(find "$CACHE_HOME/ddgx" -name '*.media' | head -1)
	[ "$(jq -r .kind "$sidecar")" = video ]
}

@test "typing after alt-v filters the videos, and ctrl-f leaves an empty search box" {
	write_two_results
	write_videos_json
	stub_videos_cmd
	run_videos
	R="$BATS_TEST_TMPDIR/results.json"

	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --videos-box "$R"
	[ "$output" = 'change-prompt(in videos > )+clear-query' ]

	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --typed "$R" 10 'magical'
	[ "${#lines[@]}" -eq 1 ]
	[[ "${lines[0]}" == 0$'\t'* ]]

	# Back to the web: "your channel" in the box would be searched for.
	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --toggle "$R"
	[[ "$output" == *'change-prompt(search > )+change-query:' ]]
}

@test "a second alt-v within the hour costs no fetch" {
	write_two_results
	write_videos_json
	stub_videos_cmd

	run_videos
	run_videos

	[ "$status" -eq 0 ]
	[ "$(cat "$BATS_TEST_TMPDIR/videos.count")" -eq 1 ]
}

@test "a failed fetch keeps the set on screen and says so" {
	write_two_results
	printf '#!/usr/bin/env bash\nexit 1\n' >"$STUB_BIN/videos-cmd"
	chmod +x "$STUB_BIN/videos-cmd"

	run_videos

	[ "$status" -eq 0 ]
	[ "$(jq -r '.[0].title' "$BATS_TEST_TMPDIR/results.json")" = 'First hit' ]
	grep -q 'could not fetch your videos' "$BATS_TEST_TMPDIR/results.json.note"
	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --videos-box "$BATS_TEST_TMPDIR/results.json"
	[ -z "$output" ]
}

@test "with no key anywhere, alt-v says where to put one and fetches nothing" {
	write_two_results
	write_videos_json
	stub_videos_cmd

	run env -u YOUTUBE_API_KEY -u YOUTUBE_CHANNEL_ID PATH="$STUB_BIN:$PATH" \
		XDG_CACHE_HOME="$CACHE_HOME" DDGX_VIDEOS_CMD="$STUB_BIN/videos-cmd" \
		bash "$DDGX" --videos "$BATS_TEST_TMPDIR/results.json"

	[ "$status" -eq 0 ]
	[ ! -f "$BATS_TEST_TMPDIR/videos.count" ]
	grep -q 'absent-youtube.json' "$BATS_TEST_TMPDIR/results.json.note"
}

@test "the popup decrypts the key from pass, because it does not load ~/.envrc" {
	write_two_results
	write_videos_json
	stub_videos_cmd
	printf '{"channel":"UCfromconfig","key_pass":"personal/YT"}\n' >"$BATS_TEST_TMPDIR/youtube.json"
	cat >"$STUB_BIN/gpg" <<EOF
#!/usr/bin/env bash
[ "\${*: -1}" = "$BATS_TEST_TMPDIR/store/personal/YT.gpg" ] && printf 'key-from-pass'
EOF
	chmod +x "$STUB_BIN/gpg"

	run env -u YOUTUBE_API_KEY -u YOUTUBE_CHANNEL_ID PATH="$STUB_BIN:$PATH" \
		XDG_CACHE_HOME="$CACHE_HOME" DDGX_VIDEOS_CMD="$STUB_BIN/videos-cmd" \
		DDGX_YOUTUBE_CONFIG="$BATS_TEST_TMPDIR/youtube.json" \
		PASSWORD_STORE_DIR="$BATS_TEST_TMPDIR/store" \
		bash "$DDGX" --videos "$BATS_TEST_TMPDIR/results.json"

	[ "$status" -eq 0 ]
	[ "$(cat "$BATS_TEST_TMPDIR/videos.env")" = 'key-from-pass UCfromconfig' ]
	[ "$(cat "$BATS_TEST_TMPDIR/results.json.engine")" = videos ]
}

@test "alt-v is bound in the picker" {
	grep -qF "alt-v:execute(\$SELF --videos" "$DDGX"
}

# --------------------------------------------------------------------------
# Pdfs and the default path's rescue
#
# Both start from a page this process fetched, which --file skips, so the
# fixtures are served from loopback. Python picks the port and prints it; -u
# keeps that line out of a buffer, and 3>&- keeps bats from waiting on the
# server after the test.
# --------------------------------------------------------------------------

serve_fixtures() {
	python3 -u -m http.server 0 --bind 127.0.0.1 --directory "$FIXTURES" \
		>"$BATS_TEST_TMPDIR/http.log" 2>&1 3>&- &
	HTTP_PID=$!
	local i
	for i in $(seq 50); do
		SERVED=$(sed -nE 's#.*(http://127\.0\.0\.1:[0-9]+/).*#\1#p' "$BATS_TEST_TMPDIR/http.log" | head -1)
		[ -z "$SERVED" ] || return 0
		sleep 0.1
	done
	return 1
}

run_served() {
	run env PATH="$STUB_BIN:$PATH" TMPDIR="$BATS_TEST_TMPDIR" \
		DDGX_C4AI_CONFIG="$BATS_TEST_TMPDIR/crawl4ai.json" \
		node "$READABLE" "$@"
}

# Not a pdf a reader could open: the stub is what reads it, and it only
# records the magic number the extractor sniffed for.
write_pdf_fixture() {
	printf '%%PDF-1.7\nthe stub reads this, not poppler\n' >"$FIXTURES/$1"
}

# pdftotext as poppler answers: hard line breaks, a form feed between pages,
# bullets the way the pdf drew them.
stub_pdftotext() {
	cat >"$STUB_BIN/pdftotext" <<EOF
#!/usr/bin/env bash
head -c 5 >"$BATS_TEST_TMPDIR/pdftotext.magic"
cat >/dev/null
printf 'Surge protection data sheet\n\nThe panel survives a strike that would\ntake a lesser one down.\n\f• Rated for 300 kA\n• Replaceable modules\n'
EOF
	chmod +x "$STUB_BIN/pdftotext"
}

# A page whose body arrives by script, the shape IMDb serves.
write_shell_fixture() {
	printf '%s\n' '<!doctype html><html><head><title>A name page</title>' \
		'<script src="/app.js"></script></head><body><div id="root"></div></body></html>' \
		>"$FIXTURES/shell.html"
}

@test "a pdf link reads through pdftotext" {
	write_pdf_fixture sheet.pdf
	stub_pdftotext
	serve_fixtures

	run_served --url "${SERVED}sheet.pdf" --stats

	[ "$status" -eq 0 ]
	[[ "$output" == *"Surge protection data sheet"* ]]
	[[ "$output" == *"- Rated for 300 kA"* ]]
	[[ "$output" == *"characters of pdf text via pdftotext]"* ]]
	# Nothing was dropped, so a kept-N-of-N line would only be noise.
	[[ "$output" != *"[kept "* ]]
	[ "$(cat "$BATS_TEST_TMPDIR/pdftotext.magic")" = '%PDF-' ]
}

@test "a pdf served as a generic binary is still read as one" {
	write_pdf_fixture sheet.bin
	stub_pdftotext
	serve_fixtures

	run_served --url "${SERVED}sheet.bin"

	[ "$status" -eq 0 ]
	[[ "$output" == *"Surge protection data sheet"* ]]
}

@test "a viewer page that frames a pdf reads as the pdf" {
	write_pdf_fixture sheet.pdf
	printf '%s\n' '<!doctype html><html><head><title>Download</title></head><body>' \
		'<iframe src="/sheet.pdf?x-sign=abc" id="mainFrame"></iframe></body></html>' \
		>"$FIXTURES/viewer.html"
	stub_pdftotext
	write_c4ai_config
	stub_curl_ok
	serve_fixtures

	run_served --url "${SERVED}viewer.html"

	[ "$status" -eq 0 ]
	[[ "$output" == *"Surge protection data sheet"* ]]
	[[ "$output" == *"from the file this page frames]"* ]]
	# The document was in hand, so nothing was rendered to find it.
	[ ! -f "$BATS_TEST_TMPDIR/curl.args" ]
}

@test "a page that builds its body in JavaScript is rendered on the cluster without --deep" {
	write_shell_fixture
	write_c4ai_config
	stub_curl_ok
	stub_chrome
	serve_fixtures

	run_served --url "${SERVED}shell.html"

	[ "$status" -eq 0 ]
	[[ "$output" == *"The cluster renderer reached this page"* ]]
	[[ "$output" == *"[step 2: crawl4ai fit filter over the cluster renderer]"* ]]
	[ ! -f "$BATS_TEST_TMPDIR/chrome.log" ]
	# /crawl, and told to wait: /md answers before a bot challenge has run.
	grep -q 'https://renderer.invalid/crawl"' "$BATS_TEST_TMPDIR/curl.stdin"
	grep -q 'wait_until' "$BATS_TEST_TMPDIR/curl.stdin"
	grep -q 'delay_before_return_html' "$BATS_TEST_TMPDIR/curl.stdin"
}

@test "a thin render is remembered, so the next preview does not ask again" {
	write_shell_fixture
	write_c4ai_config
	stub_curl_ok 'Tap to unmute'
	serve_fixtures

	run_served --url "${SERVED}shell.html"
	[ "$status" -ne 0 ]
	[[ "$output" == *"no article found"* ]]

	run_served --url "${SERVED}shell.html"
	[ "$status" -ne 0 ]
	[[ "$output" == *"no article found"* ]]

	[ "$(wc -l <"$BATS_TEST_TMPDIR/curl.args")" -eq 1 ]
}

@test "a document handed over with --file never reaches the cluster" {
	write_shell_fixture
	write_c4ai_config
	stub_curl_ok

	run_served --file "$FIXTURES/shell.html" --url "$DEEP_URL"

	[ "$status" -ne 0 ]
	[[ "$output" == *"no article found"* ]]
	[ ! -f "$BATS_TEST_TMPDIR/curl.args" ]
}

@test "a scanned pdf says why it holds no text" {
	write_pdf_fixture scan.pdf
	cat >"$STUB_BIN/pdftotext" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
EOF
	chmod +x "$STUB_BIN/pdftotext"
	serve_fixtures

	run_served --url "${SERVED}scan.pdf"

	[ "$status" -ne 0 ]
	[[ "$output" == *"no text layer, most likely a scan"* ]]
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

@test "web search asks for ten results by default" {
	cat >"$STUB_BIN/ddgr" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >"$BATS_TEST_TMPDIR/ddgr.args"
printf '%s\n' '[{"title":"One","url":"https://example.com/one","abstract":"x"}]'
EOF
	chmod +x "$STUB_BIN/ddgr"
	seed_cache "https://example.com/one" "one page"

	run_ddgx -d "one"

	[ "$status" -eq 0 ]
	[[ "$(cat "$BATS_TEST_TMPDIR/ddgr.args")" == *'--num 10'* ]]
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

stub_nvim_capture() {
	cat >"$STUB_BIN/nvim" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$BATS_TEST_TMPDIR/nvim.args"
while [ "$#" -gt 0 ]; do
	if [ "$1" = "-q" ]; then
		cp "$2" "$BATS_TEST_TMPDIR/quickfix.txt"
		break
	fi
	shift
done
EOF
	chmod +x "$STUB_BIN/nvim"
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

@test "edit mode opens nvim with searchable matches in quickfix" {
	write_two_results
	stub_nvim_capture
	printf 'pages\n' >"$BATS_TEST_TMPDIR/results.json.typing"

	run env XDG_CACHE_HOME="$CACHE_HOME" XDG_DATA_HOME="$DATA_HOME" DDGX_TTL=0 \
		DDGX_EDITOR="$STUB_BIN/nvim" \
		bash "$DDGX" --edit "$BATS_TEST_TMPDIR/results.json" --query body 0 1

	[ "$status" -eq 0 ]
	[ "$(wc -l <"$BATS_TEST_TMPDIR/quickfix.txt")" -eq 2 ]
	grep -q 'first-hit.md:5:body of the first page' "$BATS_TEST_TMPDIR/quickfix.txt"
	grep -q 'second-hit.md:5:body of the second page' "$BATS_TEST_TMPDIR/quickfix.txt"
	grep -q '^copen$' "$BATS_TEST_TMPDIR/nvim.args"
	grep -q '<C-g>n' "$BATS_TEST_TMPDIR/nvim.args"
	grep -q '<C-g>p' "$BATS_TEST_TMPDIR/nvim.args"
	grep -q 'hlsearch' "$BATS_TEST_TMPDIR/nvim.args"
	grep -q 'ctrl-e:execute.*--query {q}' "$DDGX"
}

@test "quickfix mode gives nvim no positional note arguments" {
	write_two_results
	stub_nvim_capture
	printf 'pages\n' >"$BATS_TEST_TMPDIR/results.json.typing"

	run env XDG_CACHE_HOME="$CACHE_HOME" XDG_DATA_HOME="$DATA_HOME" DDGX_TTL=0 \
		DDGX_EDITOR="$STUB_BIN/nvim" \
		bash "$DDGX" --edit "$BATS_TEST_TMPDIR/results.json" --query body 0 1

	[ "$status" -eq 0 ]
	! grep -Fxq "$DATA_HOME/ddgx/notes/first-hit.md" "$BATS_TEST_TMPDIR/nvim.args"
	! grep -Fxq "$DATA_HOME/ddgx/notes/second-hit.md" "$BATS_TEST_TMPDIR/nvim.args"
}

@test "edit mode builds quickfix with the same slash-delimited ERE" {
	write_two_results
	stub_nvim_capture
	printf 'pages\n' >"$BATS_TEST_TMPDIR/results.json.typing"

	run env XDG_CACHE_HOME="$CACHE_HOME" XDG_DATA_HOME="$DATA_HOME" DDGX_TTL=0 \
		DDGX_EDITOR="$STUB_BIN/nvim" \
		bash "$DDGX" --edit "$BATS_TEST_TMPDIR/results.json" \
		--query '/first.*page/' 0 1

	[ "$status" -eq 0 ]
	[ "$(wc -l <"$BATS_TEST_TMPDIR/quickfix.txt")" -eq 1 ]
	grep -q 'first-hit.md:5:body of the first page' "$BATS_TEST_TMPDIR/quickfix.txt"
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
# A set on disk. The modes below run over the results file and its sidecars,
# the way the picker's bindings call them.
# --------------------------------------------------------------------------

# A picker mid-search: three results over two domains, and the query that
# produced them.
write_search_state() {
	RESULTS="$BATS_TEST_TMPDIR/results.json"
	printf '%s\n' '[{"title":"Finalizers","url":"https://kubernetes.io/docs/finalizers/","abstract":"a"},{"title":"A blog","url":"https://www.medium.com/p/1","abstract":"b"},{"title":"Nodes","url":"https://kubernetes.io/docs/nodes/","abstract":"c"}]' >"$RESULTS"
	printf '%s\n' "$1" >"$RESULTS.query"
	# The next set, pre-cached so the warming pass has nothing to fetch.
	seed_cache "https://kubernetes.io/only/" "the narrowed page"
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

@test "ctrl-o says which renderer paid for the page" {
	printf '%s\n' '[{"title":"Blocked","url":"https://blocked.invalid/x","abstract":"nope"}]' \
		>"$BATS_TEST_TMPDIR/results.json"
	# The extract names its own winner in the footer, which is where the note
	# reads it from rather than timing the call or asking a second time.
	cat >"$STUB_BIN/node" <<'EOF'
#!/usr/bin/env bash
printf 'the body the cluster renderer returned\n\n'
printf '[step 2: crawl4ai fit filter over the cluster renderer]\n'
EOF
	chmod +x "$STUB_BIN/node"

	run_action "$BATS_TEST_TMPDIR/results.json" 0 0
	[ "$status" -eq 0 ]

	# A remote render against a local browser is what the note reports. Saying
	# "the slow way" for a rung that was not slow trains you to ignore it.
	run bash "$DDGX" --header "$BATS_TEST_TMPDIR/results.json"
	[[ "$output" == *"rendered by the cluster renderer"* ]]
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
	[[ "${lines[2]}" == *"alt-h hand to pane"* ]]

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
	[ "${#lines[@]}" -eq 4 ]
	local line
	for line in "${lines[@]}"; do
		[ "$(wc -L <<<"$line")" -le 98 ]
	done
	[[ "${lines[3]}" == *'F1 help'* ]]
	[[ "${lines[3]}" == *'ctrl-f in pages'* ]]

	# The page filter's own line, after ctrl-f, has to fit as well.
	printf 'pages\n' >"$RESULTS.typing"
	run bash "$DDGX" --header "$RESULTS"
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 4 ]
	for line in "${lines[@]}"; do
		[ "$(wc -L <<<"$line")" -le 98 ]
	done
	[[ "${lines[3]}" == *'/ERE/'* ]]

	# And the follow-up box's.
	printf 'follow\n' >"$RESULTS.typing"
	run bash "$DDGX" --header "$RESULTS"
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 4 ]
	for line in "${lines[@]}"; do
		[ "$(wc -L <<<"$line")" -le 98 ]
	done
	[[ "${lines[3]}" == *'empty enter: back'* ]]
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
	# transform, not execute-silent: mode_send prints the fzf action and fzf
	# performs it, which is what lets one key close the popup on a delivery and
	# keep it open on a failure. execute-silent can do neither.
	[[ "$bind" == *"transform("* ]]
	[[ "$bind" != *"execute-silent"* ]]

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

	# A delivered hand-off closes the popup. The receipt is the paths sitting on
	# the input line of the pane underneath, which is where you are about to
	# type; a header line saying it worked would be read by nobody, because the
	# window carrying it is gone.
	[ "$output" = "abort" ]
}

@test "a hand-off that failed keeps the picker up to say so" {
	write_send_state '%999'
	stub_tmux '%7'

	run_send "$SEND_RESULTS" 0

	# Closing on a failed delivery turns the whole feature into "it did
	# nothing", which is the report this file spends a paragraph avoiding.
	[ "$status" -eq 0 ]
	[[ "$output" == *"transform-header"* ]]
	[[ "$output" != *"abort"* ]]
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
	[ -z "${HTTP_PID:-}" ] || kill "$HTTP_PID" 2>/dev/null || true
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

# ---------------------------------------------------------------------------
# The ask engine. Perplexity answers the question and its sources become
# results, so every key that works on a search result works on them.
#
# The backend is stubbed through DDGX_ASK_CMD: __ddgx.sh resolves it from
# SCRIPT_DIR, which PATH cannot override, and no test may reach the network or
# spend an API credit to find out how a row is drawn.
# ---------------------------------------------------------------------------

ASK_REPLY='{"answer":"Defrag rewrites the backend db. [1]","results":[{"id":1,"title":"Maintenance","url":"https://etcd.io/docs/maintenance/","snippet":"reclaims space","date":"2026-01-01"},{"id":2,"title":"A post","url":"https://example.com/defrag","snippet":"a blog post","date":""}]}'

stub_ask() {
	cat >"$STUB_BIN/ask" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >"$STUB_BIN/ask.argv"
cat <<'JSON'
$1
JSON
EOF
	chmod +x "$STUB_BIN/ask"
	# Sources are extracted like any other result, so keep the suite offline.
	seed_cache "https://etcd.io/docs/maintenance/" "the maintenance page"
	seed_cache "https://example.com/defrag" "the blog post"
}

# The query is the last argument the backend was handed.
asked_query() { tail -n1 "$STUB_BIN/ask.argv"; }
asked_with() { grep -qx -- "$1" "$STUB_BIN/ask.argv"; }

run_ask() {
	run env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" \
		XDG_DATA_HOME="$DATA_HOME" DDGX_TTL=0 DDGX_ASK_CMD="$STUB_BIN/ask" \
		bash "$DDGX" "$@"
}

# A picker mid-ask: the answer row, one source, and the sidecars that say which
# engine produced the set and what it said.
write_ask_state() {
	RESULTS="$BATS_TEST_TMPDIR/results.json"
	printf '%s\n' '[{"title":"answer · perplexity low","url":"","abstract":"","ref":""},{"title":"Maintenance","url":"https://etcd.io/docs/maintenance/","abstract":"reclaims space","ref":"1"}]' >"$RESULTS"
	printf '%s\n' "$1" >"$RESULTS.query"
	printf 'the answer text\n' >"$RESULTS.answer"
	printf 'pplx\n' >"$RESULTS.engine"
	# The conversation so far: the run a follow-up continues from, and the turn
	# it is up to.
	printf 'resp_seed\n1\nhigh\n' >"$RESULTS.thread"
	seed_cache "https://etcd.io/docs/maintenance/" "the maintenance page"
}

# Send a query from the box, the way enter does once the rows stop answering it.
run_submit() {
	printf '%s' "$1" >"$RESULTS.submit"
	run env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" \
		XDG_DATA_HOME="$DATA_HOME" DDGX_TTL=0 DDGX_ASK_CMD="$STUB_BIN/ask" \
		bash "$DDGX" --submit "$RESULTS" 8
}

@test "a leading ? asks rather than searches" {
	stub_ask "$ASK_REPLY"

	run_ask -d '? what does etcd defrag do'

	[ "$status" -eq 0 ]
	[[ "$output" == *"Defrag rewrites the backend db"* ]]
}

@test "the ? is a mode marker and never reaches the question" {
	stub_ask "$ASK_REPLY"

	run_ask -d '? what does etcd defrag do'

	# A question that arrives starting with punctuation is a different question.
	[ "$status" -eq 0 ]
	[ "$(asked_query)" = "what does etcd defrag do" ]
}

@test "-a asks without needing the prefix" {
	stub_ask "$ASK_REPLY"

	run_ask -d -a 'etcd defrag'

	[ "$status" -eq 0 ]
	[ "$(asked_query)" = "etcd defrag" ]
}

@test "the preset travels to the backend, and low is the default" {
	stub_ask "$ASK_REPLY"

	run_ask -d -a 'etcd defrag'

	[ "$status" -eq 0 ]
	asked_with '--preset'
	asked_with 'low'
}

@test "DDGX_PPLX_PRESET chooses the depth" {
	stub_ask "$ASK_REPLY"

	run env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" \
		XDG_DATA_HOME="$DATA_HOME" DDGX_TTL=0 DDGX_ASK_CMD="$STUB_BIN/ask" \
		DDGX_PPLX_PRESET=medium bash "$DDGX" -d -a 'etcd defrag'

	[ "$status" -eq 0 ]
	asked_with 'medium'
}

@test "a source keeps the number the answer cited it by" {
	write_ask_state 'etcd defrag'

	run bash "$DDGX" --list "$RESULTS"

	# The answer says [1]; the row that backs it has to say [1] too, not 2.
	[ "$status" -eq 0 ]
	[[ "$output" == *"[1] Maintenance"* ]]
}

@test "a web result is still numbered by position" {
	write_search_state 'kubernetes finalizers'

	run bash "$DDGX" --list "$RESULTS"

	[ "$status" -eq 0 ]
	[[ "$output" == *"1. Finalizers"* ]]
}

@test "the answer row carries no number and nowhere to go" {
	write_ask_state 'etcd defrag'

	run bash "$DDGX" --list "$RESULTS"

	[ "$status" -eq 0 ]
	local first
	first=$(printf '%s\n' "$output" | sed -n '1p' | sed 's/\x1b\[[0-9;]*m//g')
	[[ "$first" == *"answer · perplexity low"* ]]
	# No leading index, and no domain in brackets: it is not a page.
	[[ "$first" != *"1."* ]]
	[[ "$first" != *"http"* ]]
}

@test "the answer previews as the answer, not as a page with no text" {
	write_ask_state 'etcd defrag'

	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --preview "$RESULTS" 0

	[ "$status" -eq 0 ]
	[[ "$output" == *"the answer text"* ]]
	[[ "$output" != *"no page text"* ]]
}

@test "a source of the answer previews as its page" {
	write_ask_state 'etcd defrag'

	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --preview "$RESULTS" 1

	[ "$status" -eq 0 ]
	[[ "$output" == *"the maintenance page"* ]]
}

@test "the answer keeps as a note named from the question" {
	write_ask_state 'why does etcd defrag block'
	cat >"$STUB_BIN/fake-editor" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$BATS_TEST_TMPDIR/edited"
EOF
	chmod +x "$STUB_BIN/fake-editor"

	run env XDG_CACHE_HOME="$CACHE_HOME" XDG_DATA_HOME="$DATA_HOME" \
		BATS_TEST_TMPDIR="$BATS_TEST_TMPDIR" DDGX_EDITOR="$STUB_BIN/fake-editor" \
		bash "$DDGX" --edit "$RESULTS" 0

	# Named for the question, because "answer-perplexity-low" would name every
	# answer ever kept the same thing.
	[ "$status" -eq 0 ]
	local note="$DATA_HOME/ddgx/notes/why-does-etcd-defrag-block.md"
	[ -f "$note" ]
	grep -q 'the answer text' "$note"
	grep -q 'why does etcd defrag block' "$note"
}

@test "the sources are not trimmed to the result count" {
	stub_ask "$ASK_REPLY"

	run_ask -d -n 1 -a 'etcd defrag'

	# The answer numbers its own sources, so a list cut to -n would leave a
	# claim marked [2] pointing at a row that is not on screen.
	[ "$status" -eq 0 ]
	[[ "$output" == *"Maintenance"* ]]
	[[ "$output" == *"A post"* ]]
}

@test "an answer that came back empty is reported rather than drawn" {
	stub_ask '{"answer":"","results":[]}'

	run_ask -d -a 'etcd defrag'

	[ "$status" -ne 0 ]
	[[ "$output" == *"empty"* ]]
}

@test "an answer with no sources is still an answer" {
	stub_ask '{"answer":"Nothing cited, still true.","results":[]}'

	run_ask -d -a 'etcd defrag'

	[ "$status" -eq 0 ]
	[[ "$output" == *"Nothing cited, still true."* ]]
}

@test "the header says ask for a set an answer produced" {
	write_ask_state 'etcd defrag'

	run bash "$DDGX" --header "$RESULTS"

	# The same words mean two different things depending on which engine ran.
	[ "$status" -eq 0 ]
	[[ "$output" == *"ask: etcd defrag"* ]]
}

@test "the header says query for a web set, including one written before engines existed" {
	write_search_state 'kubernetes finalizers'

	run bash "$DDGX" --header "$RESULTS"

	[ "$status" -eq 0 ]
	[[ "$output" == *"query: kubernetes finalizers"* ]]
}

@test "switching back to web takes the answer down with it" {
	write_ask_state 'etcd defrag'
	stub_ddgr '[{"title":"Narrowed","url":"https://kubernetes.io/only/","abstract":"z"}]'
	run_submit 'etcd defrag'

	# A stale answer under a set with no row to show it is a file that can only
	# ever be read by mistake.
	[ "$status" -eq 0 ]
	[ "$(head -n1 "$RESULTS.engine")" = "ddgr" ]
	[ ! -f "$RESULTS.answer" ]
}

@test "?? asks harder, and high is the default depth" {
	stub_ask "$ASK_REPLY"

	run_ask -d '?? why do pods stay terminating'

	# One mark for the question asked in passing, two for the one you sit with.
	[ "$status" -eq 0 ]
	asked_with 'high'
	[ "$(asked_query)" = "why do pods stay terminating" ]
}

@test "DDGX_DEEP_PRESET chooses what the second mark means" {
	stub_ask "$ASK_REPLY"

	run env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" \
		XDG_DATA_HOME="$DATA_HOME" DDGX_TTL=0 DDGX_ASK_CMD="$STUB_BIN/ask" \
		DDGX_DEEP_PRESET=xhigh bash "$DDGX" -d '?? trace this claim'

	[ "$status" -eq 0 ]
	asked_with 'xhigh'
}

@test "--preset reaches the depths no prefix offers" {
	stub_ask "$ASK_REPLY"

	run_ask -d --preset xhigh 'trace this claim'

	# 100 steps and minutes of waiting is a deliberate spend, so it is spelled
	# out rather than sitting one keystroke away from a passing question.
	[ "$status" -eq 0 ]
	asked_with 'xhigh'
}

@test "the row names the preset that produced the answer" {
	stub_ask "$ASK_REPLY"

	run_ask -d '?? why do pods stay terminating'

	# An answer that reads thin should name the preset behind it, so the fix is
	# visible: one more question mark next time.
	[ "$status" -eq 0 ]
	[[ "$output" == *"answer · perplexity high"* ]]
}

# ---------------------------------------------------------------------------
# Chat. An answer that ends "I can narrow this to X or Y" is inviting a second
# turn, and the thread id is what lets the next question take it up.
# ---------------------------------------------------------------------------

FOLLOW_REPLY='{"id":"resp_second","answer":"Because the member blocks while it rebuilds.","results":[{"id":1,"title":"Maintenance","url":"https://etcd.io/docs/maintenance/","snippet":"blocks","date":""}]}'

# Send a follow-up the way enter does from the follow-up box: the question
# waits in the submit file.
run_follow() {
	printf '%s' "$1" >"$RESULTS.submit"
	run env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" \
		XDG_DATA_HOME="$DATA_HOME" DDGX_TTL=0 DDGX_ASK_CMD="$STUB_BIN/ask" \
		bash "$DDGX" --follow "$RESULTS" 8
}

@test "a follow-up carries the thread, so it can say it" {
	write_ask_state 'etcd defrag'
	stub_ask "$FOLLOW_REPLY"

	run_follow 'why does it block'

	# Without the id the question arrives with no idea what the last answer was
	# about, which is two unrelated searches wearing a conversation's clothes.
	[ "$status" -eq 0 ]
	asked_with '--continue'
	asked_with 'resp_seed'
	[ "$(asked_query)" = "why does it block" ]
}

@test "a follow-up keeps the conversation and puts the newest turn on top" {
	write_ask_state 'etcd defrag'
	stub_ask "$FOLLOW_REPLY"

	run_follow 'why does it block'

	[ "$status" -eq 0 ]
	# The question heads its own turn, and the turn you just asked for is the
	# one the preview opens on.
	[ "$(head -n1 "$RESULTS.answer")" = "## why does it block" ]
	grep -q 'Because the member blocks' "$RESULTS.answer"
	# Nothing said earlier is lost.
	grep -q 'the answer text' "$RESULTS.answer"
	local new old
	new=$(grep -n 'Because the member blocks' "$RESULTS.answer" | cut -d: -f1)
	old=$(grep -n 'the answer text' "$RESULTS.answer" | cut -d: -f1)
	[ "$new" -lt "$old" ]
}

@test "each turn carries its own numbered sources" {
	write_ask_state 'etcd defrag'
	stub_ask "$FOLLOW_REPLY"

	run_follow 'why does it block'

	# The rows only ever show the newest turn's sources, so a [1] further up the
	# transcript has to resolve against the turn it belongs to.
	[ "$status" -eq 0 ]
	grep -q '^\[1\]: https://etcd.io/docs/maintenance/' "$RESULTS.answer"
}

@test "a follow-up advances the thread and the turn count" {
	write_ask_state 'etcd defrag'
	stub_ask "$FOLLOW_REPLY"

	run_follow 'why does it block'

	[ "$status" -eq 0 ]
	[ "$(sed -n '1p' "$RESULTS.thread")" = "resp_second" ]
	[ "$(sed -n '2p' "$RESULTS.thread")" = "2" ]
	# The depth is the one the conversation was started at, which the seeded
	# thread records as high.
	[ "$(jq -r '.[0].title' "$RESULTS")" = "answer · perplexity high · turn 2" ]
}

@test "a fresh ask starts a new conversation rather than continuing the last" {
	write_ask_state 'etcd defrag'
	stub_ask "$ASK_REPLY"

	run_submit '? something else entirely'

	# Rewriting the query is a new question, not the next one: continuing the
	# thread would answer it in the shadow of a conversation it has nothing to
	# do with.
	[ "$status" -eq 0 ]
	[[ "$(cat "$STUB_BIN/ask.argv")" != *"--continue"* ]]
	[ "$(sed -n '2p' "$RESULTS.thread")" = "1" ]
	[ "$(head -n1 "$RESULTS.answer")" = "## something else entirely" ]
}

@test "switching back to web ends the conversation" {
	write_ask_state 'etcd defrag'
	stub_ddgr '[{"title":"Narrowed","url":"https://kubernetes.io/only/","abstract":"z"}]'
	run_submit 'etcd defrag'

	# A thread id under a web set would let a later follow-up continue a
	# conversation the picker has no trace of.
	[ "$status" -eq 0 ]
	[ ! -f "$RESULTS.thread" ]
}

@test "a conversation is held at the depth it was started at" {
	write_ask_state 'etcd defrag'
	stub_ask "$FOLLOW_REPLY"

	run_follow 'why does it block'

	# The seeded thread was started at high. A follow-up that fell back to the
	# cheap default would answer the harder question with less effort than the
	# one that opened the conversation.
	[ "$status" -eq 0 ]
	asked_with 'high'
	[[ "$(cat "$STUB_BIN/ask.argv")" != *"low"* ]]
	[ "$(sed -n '3p' "$RESULTS.thread")" = "high" ]
}

# ---------------------------------------------------------------------------
# enter. On a page it opens the page. On the answer it points the box at the
# next question, and there it sends it: enter, type, enter, read.
# ---------------------------------------------------------------------------

@test "the picker binds enter through the dispatcher" {
	local bind
	bind=$(grep -F -- '--bind="enter:' "$DDGX")

	# A key that means two things has to ask what the row is, which is the same
	# contract ctrl-o already runs on.
	[ -n "$bind" ]
	[[ "$bind" == *"transform("* ]]
	[[ "$bind" == *"--enter"* ]]
}

@test "enter on the answer row turns the box into the follow-up" {
	write_ask_state 'etcd defrag'

	run bash "$DDGX" --enter "$RESULTS" 0 8

	# The question is typed on the same screen, under the answer it follows:
	# nothing here may take the terminal away from the picker.
	[ "$status" -eq 0 ]
	[[ "$output" == *"change-prompt(follow up > )"* ]]
	[[ "$output" == *"clear-query"* ]]
	[[ "$output" != *"execute("* ]]
	[[ "$output" != *"accept"* ]]
	[ "$(cat "$RESULTS.typing")" = follow ]
}

@test "enter in the follow-up box sends the question into the conversation" {
	write_ask_state 'etcd defrag'
	printf 'follow\n' >"$RESULTS.typing"

	run bash "$DDGX" --enter "$RESULTS" 0 8 'why does it (still) block'

	# The list is rebuilt so the new turn is on screen, and the box goes back
	# to the query once the turn is in.
	[ "$status" -eq 0 ]
	[[ "$output" == *"--follow"* ]]
	[[ "$output" == *"reload("* ]]
	[[ "$output" == *"--box"* ]]
	# The question waits in a file: parens in it would end the printed action.
	[ "$(cat "$RESULTS.submit")" = 'why does it (still) block' ]
	[[ "$output" != *'still'* ]]
}

@test "an empty enter in the follow-up box puts the query back" {
	write_ask_state 'etcd defrag'
	printf 'follow\n' >"$RESULTS.typing"

	run bash "$DDGX" --enter "$RESULTS" 0 8 ''

	[ "$status" -eq 0 ]
	[[ "$output" == *"change-prompt(search > )"* ]]
	# The seeded conversation runs at high, so its mark is ??.
	[[ "$output" == *"change-query:?? etcd defrag" ]]
	[ "$(cat "$RESULTS.typing")" = web ]
	[ ! -e "$RESULTS.submit" ]
}

@test "typing a follow-up searches nothing until enter" {
	write_ask_state 'etcd defrag'
	printf 'follow\n' >"$RESULTS.typing"
	stub_ddgr '[{"title":"Narrowed","url":"https://kubernetes.io/only/","abstract":"z"}]'
	stub_ask "$FOLLOW_REPLY"

	run env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" \
		XDG_DATA_HOME="$DATA_HOME" DDGX_TTL=0 DDGX_ASK_CMD="$STUB_BIN/ask" \
		DDGX_SUGGEST_DELAY=0 bash "$DDGX" --typed "$RESULTS" 8 'why does it block'

	# Plain words in the web box would be a DuckDuckGo search on the pause.
	# Here they are half a question, and the answer stays on screen.
	[ "$status" -eq 0 ]
	[[ "$output" == *"answer · perplexity"* ]]
	[ "$(head -n1 "$RESULTS.engine")" = pplx ]
	[ "$(head -n1 "$RESULTS.query")" = 'etcd defrag' ]
	[ ! -e "$STUB_BIN/ask.argv" ]
}

@test "enter on a source row still opens the page" {
	write_ask_state 'etcd defrag'

	run bash "$DDGX" --enter "$RESULTS" 1 8

	# Enter has always opened the thing under the cursor, and a cited page is a
	# page.
	[ "$status" -eq 0 ]
	[ "$output" = "accept" ]
}

@test "enter on a web result still opens the page" {
	write_search_state 'kubernetes finalizers'

	run bash "$DDGX" --enter "$RESULTS" 0 8

	[ "$status" -eq 0 ]
	[ "$output" = "accept" ]
}

@test "the follow mode sends the waiting question and spends the file" {
	write_ask_state 'etcd defrag'
	stub_ask "$FOLLOW_REPLY"

	run_follow 'why does it block'

	[ "$status" -eq 0 ]
	[ ! -e "$RESULTS.submit" ]
	asked_with '--continue'
	asked_with 'resp_seed'
	[ "$(asked_query)" = "why does it block" ]
	[ "$(sed -n '2p' "$RESULTS.thread")" = "2" ]
}

@test "following a web set says so instead of asking into nothing" {
	write_search_state 'kubernetes finalizers'

	run_follow 'why does it block'

	# enter only opens the follow-up box over an answer, but the mode answers
	# for itself rather than asking a question with no conversation behind it.
	[ "$status" -eq 0 ]
	grep -q 'came from a web search' "$RESULTS.note"
}

@test "the answer pane names the key that continues the conversation" {
	write_ask_state 'etcd defrag'

	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --preview "$RESULTS" 0

	# A conversation nobody knows how to continue reads as a dead end, and this
	# file's own rule is that the pane names the key.
	[ "$status" -eq 0 ]
	[[ "$output" == *"enter, then type a follow-up"* ]]
}

# --------------------------------------------------------------------------
# @ — the manual, searched over the page bodies.
# --------------------------------------------------------------------------

# A corpus of four pages standing in for the 191 real ones, holding every shape
# the ranker has to survive: prose, a term that only appears inside markup, and
# a page whose match is split across two lines.
write_docs_corpus() {
	DOCS_DIR="$BATS_TEST_TMPDIR/claude-docs"
	mkdir -p "$DOCS_DIR/pages/agent-sdk"
	cat >"$DOCS_DIR/llms.txt" <<'INDEX'
# Claude Code Docs

## Reference
- [Hooks reference](https://code.claude.com/docs/en/hooks.md): Reference for hook events.
- [Automate actions with hooks](https://code.claude.com/docs/en/hooks-guide.md): A quickstart.
- [Settings reference](https://code.claude.com/docs/en/settings-reference.md): Every setting.
- [Agent SDK hooks](https://code.claude.com/docs/en/agent-sdk/hooks.md): SDK hooks.
INDEX
	cat >"$DOCS_DIR/pages/hooks.md" <<'PAGE'
> ## Documentation Index
> Fetch the complete documentation index at: https://code.claude.com/docs/llms.txt

# Hooks reference

A matcher filters which tool calls a PreToolUse hook sees.
The matcher is a string, and precedence runs from the narrowest.
PreToolUse fires before the tool runs. The matcher matches the tool name.
PAGE
	cat >"$DOCS_DIR/pages/hooks-guide.md" <<'PAGE'
# Automate actions with hooks

<Frame>
  <img src="x.svg" alt="A diagram naming every matcher and its precedence" data-path="images/x.svg" />
</Frame>

Hooks run shell commands. This page never says the other word.
PAGE
	cat >"$DOCS_DIR/pages/settings-reference.md" <<'PAGE'
# Settings reference

Project settings live in settings.json and override the user file.
Pass --skip-checks to bypass them.
The hookSpecificOutput:additionalContext field carries text back.
PAGE
	cat >"$DOCS_DIR/pages/agent-sdk/hooks.md" <<'PAGE'
# Agent SDK hooks

The SDK exposes a matcher too.
Its precedence is documented alongside the TypeScript types.
PAGE
	# Seed the extract cache for every page in the corpus. Dump mode extracts
	# what it renders, and the url a docs hit carries is the live HTML page, so
	# without this the docs tests reach code.claude.com for real: slow, and
	# flaky in the way that matters, since a fetch slow enough to fall back can
	# trip the very curl tripwire these tests use to prove they stayed offline.
	local slug
	for slug in hooks hooks-guide settings-reference agent-sdk/hooks; do
		seed_cache "https://code.claude.com/docs/en/$slug" "extract of $slug"
	done
}

# curl that fails loudly. Every docs test runs against a corpus already on
# disk, so a test that reaches the network is a test that stopped proving what
# it says it proves.
stub_curl_tripwire() {
	cat >"$STUB_BIN/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl was called: $*" >&2
exit 99
EOF
	chmod +x "$STUB_BIN/curl"
}

# ddgr that fails the same way, so "scoped to the docs" is proved rather than
# assumed: a docs search that quietly fell through to the web would die here.
stub_ddgr_tripwire() {
	cat >"$STUB_BIN/ddgr" <<'EOF'
#!/usr/bin/env bash
echo "ddgr was called: $*" >&2
exit 99
EOF
	chmod +x "$STUB_BIN/ddgr"
}

run_docs() {
	write_docs_corpus
	stub_curl_tripwire
	stub_ddgr_tripwire
	run env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" \
		XDG_DATA_HOME="$DATA_HOME" DDGX_TTL=0 DDGX_DOCS_DIR="$DOCS_DIR" \
		DDGX_NO_NETWORK=1 \
		bash "$DDGX" "$@"
}

# The result set as JSON, which is what the picker and every mode read, and
# what the rendered dump wraps to the width of a pane before showing.
run_docs_json() {
	write_docs_corpus
	stub_curl_tripwire
	stub_ddgr_tripwire
	DOCS_SET="$BATS_TEST_TMPDIR/docs-result.json"
	run env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" \
		XDG_DATA_HOME="$DATA_HOME" DDGX_TTL=0 DDGX_DOCS_DIR="$DOCS_DIR" \
		DDGX_NO_NETWORK=1 \
		bash -c "source '$DDGX' >/dev/null 2>&1 || true
			search_docs '$DOCS_SET' 8 '$1' >/dev/null"
}

@test "a leading @ searches the manual rather than the web" {
	run_docs -d -l 0 '@ matcher precedence'

	[ "$status" -eq 0 ]
	[[ "$output" != *"ddgr was called"* ]]
	[[ "$output" == *"Hooks reference"* ]]
}

@test "the @ is a mode marker and never reaches the terms" {
	# A term arriving as "@matcher" matches nothing, so a hit proves the mark
	# came off before the search.
	run_docs -d -l 0 '@matcher'

	[ "$status" -eq 0 ]
	[[ "$output" == *"Hooks reference"* ]]
}

@test "--docs looks up the manual without needing the prefix" {
	run_docs -d -l 0 --docs 'matcher precedence'

	[ "$status" -eq 0 ]
	[[ "$output" == *"Hooks reference"* ]]
}

@test "a hit points at the page, not at the .md twin it was searched in" {
	# The whole reason preview, ctrl-e, ctrl-a and enter need no new code: the
	# url is the same kind of url a web result carries. The .md twin reads
	# worse than the extractor's render of the page, and __readable.mjs refuses
	# it outright as text/markdown.
	run_docs -d -l 0 '@ matcher precedence'

	[ "$status" -eq 0 ]
	[[ "$output" == *"https://code.claude.com/docs/en/hooks"* ]]
	[[ "$output" != *"hooks.md"* ]]
}

@test "a page qualifies only when every term is in it" {
	# hooks-guide.md holds neither word outside its markup.
	run_docs -d -l 0 '@ matcher precedence'

	[ "$status" -eq 0 ]
	[[ "$output" == *"Hooks reference"* ]]
	[[ "$output" == *"Agent SDK hooks"* ]]
	[[ "$output" != *"Automate actions with hooks"* ]]
}

@test "the snippet carries the terms, not the lines before them" {
	# The tool this replaces reported a page's best single LINE, so a result
	# routinely showed one term out of two and read like a false positive. The
	# assertion reads the abstract rather than the rendered dump, which wraps
	# the snippet across however many columns the pane happens to have.
	run_docs_json 'matcher precedence'

	[ "$status" -eq 0 ]
	abstract=$(jq -r '.[0].abstract' "$DOCS_SET")
	[[ "$abstract" == *"matcher"* ]]
	[[ "$abstract" == *"precedence"* ]]
}

@test "a snippet wider than the cap keeps the match, not the run-up to it" {
	# A window is three lines and a term can sit in the last of them, so
	# trimming from the left edge is how a snippet arrives showing the two
	# lines BEFORE the match and none of it.
	write_docs_corpus
	stub_curl_tripwire
	# Written after the fixture, and read by a call that does not rewrite it.
	{
		printf '# Padding\n\n'
		printf 'Filler prose that carries none of the words being looked for.\n'
		printf 'More filler, equally beside the point, and quite long as well.\n'
		printf 'At the very end of the window sits the word obscureneedle.\n'
	} >"$DOCS_DIR/pages/settings-reference.md"

	run env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" \
		XDG_DATA_HOME="$DATA_HOME" DDGX_TTL=0 DDGX_DOCS_DIR="$DOCS_DIR" \
		DDGX_NO_NETWORK=1 \
		DDGX_DOCS_SNIPPET=60 bash -c "source '$DDGX' >/dev/null 2>&1 || true
			search_docs '$BATS_TEST_TMPDIR/cut.json' 8 'obscureneedle' >/dev/null
			jq -r '.[0].abstract' '$BATS_TEST_TMPDIR/cut.json'"

	[ "$status" -eq 0 ]
	[[ "$output" == *"obscureneedle"* ]]
}

@test "a term found only inside markup is not a mention" {
	# hooks-guide.md carries both words, but only in an <img> alt attribute
	# describing a diagram. Counting that is how a search invents a hit.
	run_docs -d -l 0 '@ matcher precedence'

	[ "$status" -eq 0 ]
	[[ "$output" != *"Automate actions with hooks"* ]]
}

@test "a term is a literal string, not a pattern" {
	# settings.json must not match settingsXjson, which is what a term handed
	# to a regex engine would do.
	run_docs -d -l 0 '@ settings.json'

	[ "$status" -eq 0 ]
	[[ "$output" == *"Settings reference"* ]]
}

@test "a flag is a term, not an exclusion" {
	# The corpus is a CLI manual, so a query opening with a dash is far more
	# likely to be a flag than a word to drop. Reading --flag as DuckDuckGo's
	# "exclude this" throws the whole query away and then blames the user for
	# an empty one.
	run_docs -d -l 0 '@ --skip-checks'

	[ "$status" -eq 0 ]
	[[ "$output" == *"Settings reference"* ]]
}

@test "a colon in a term is content, not an operator" {
	run_docs -d -l 0 '@ hookSpecificOutput:additionalContext'

	[ "$status" -eq 0 ]
	[[ "$output" == *"Settings reference"* ]]
}

@test "duckduckgo's own operators are still dropped, by name" {
	# There is one site in the manual, so site: cannot narrow it and searching
	# for the literal string "site:code.claude.com" finds nothing.
	run_docs -d -l 0 '@ site:code.claude.com matcher precedence'

	[ "$status" -eq 0 ]
	[[ "$output" == *"Hooks reference"* ]]
}

@test "a docs query returns nothing unless one page carries every term" {
	run_docs -d -l 0 '@ matcher precedence zzzznotaword'

	[ "$status" -eq 1 ]
	[[ "$output" == *"nothing in the docs mentions"* ]]
	[[ "$output" != *"Hooks reference"* ]]
}

@test "nothing in the manual is an error naming what was looked for" {
	run_docs -d '@ zzzznotaword qqqqnope'

	[ "$status" -eq 1 ]
	[[ "$output" == *"nothing in the docs mentions"* ]]
	[[ "$output" == *"zzzznotaword"* ]]
}

@test "a quoted phrase is one term" {
	run_docs -d -l 0 '@ "the matcher matches"'

	[ "$status" -eq 0 ]
	[[ "$output" == *"Hooks reference"* ]]
	[[ "$output" != *"Agent SDK hooks"* ]]
}

@test "a corpus already on disk is not fetched again" {
	# The copy refreshes on the ordinary TTL. A search that re-fetched 191
	# pages every time would be a mirror maintained by hand with extra steps.
	run_docs -d -l 0 '@ matcher precedence'

	[ "$status" -eq 0 ]
	[[ "$output" != *"curl was called"* ]]
}

@test "a page missing from the copy is fetched, once" {
	write_docs_corpus
	stub_ddgr_tripwire
	rm -f "$DOCS_DIR/pages/agent-sdk/hooks.md"
	cat >"$STUB_BIN/curl" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$BATS_TEST_TMPDIR/curl.argv"
for a in "\$@"; do
	[ "\$prev" = "-o" ] && out="\$a"
	prev="\$a"
done
printf 'The SDK exposes a matcher too and its precedence.\n' >"\$out"
EOF
	chmod +x "$STUB_BIN/curl"

	run env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" \
		XDG_DATA_HOME="$DATA_HOME" DDGX_TTL=0 DDGX_DOCS_DIR="$DOCS_DIR" \
		DDGX_NO_NETWORK=1 \
		bash "$DDGX" --docs -d -l 0 'matcher precedence'

	[ "$status" -eq 0 ]
	[ "$(grep -c 'agent-sdk/hooks.md' "$BATS_TEST_TMPDIR/curl.argv")" -eq 1 ]
	[[ "$output" == *"Agent SDK hooks"* ]]
}

@test "a page that failed to fetch leaves no half-written file behind" {
	# A truncated page is worse than an absent one: it still qualifies for a
	# match and reports a hit from whichever half arrived.
	write_docs_corpus
	stub_ddgr_tripwire
	rm -f "$DOCS_DIR/pages/agent-sdk/hooks.md"
	cat >"$STUB_BIN/curl" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
	[ "$prev" = "-o" ] && out="$a"
	prev="$a"
done
printf 'half a page' >"$out"
exit 22
EOF
	chmod +x "$STUB_BIN/curl"

	run env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" \
		XDG_DATA_HOME="$DATA_HOME" DDGX_TTL=0 DDGX_DOCS_DIR="$DOCS_DIR" \
		DDGX_NO_NETWORK=1 \
		bash "$DDGX" --docs -d -l 0 'matcher precedence'

	[ "$status" -eq 0 ]
	[ ! -e "$DOCS_DIR/pages/agent-sdk/hooks.md" ]
	[ ! -e "$DOCS_DIR/pages/agent-sdk/hooks.md.part" ]
}

@test "the header says docs for a set the manual produced" {
	R="$BATS_TEST_TMPDIR/docs-set.json"
	printf '%s\n' '[{"title":"Hooks reference","url":"https://code.claude.com/docs/en/hooks","abstract":"x"}]' >"$R"
	printf 'matcher precedence\n' >"$R.query"
	printf 'docs\n' >"$R.engine"

	run env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" \
		XDG_DATA_HOME="$DATA_HOME" DDGX_TTL=0 bash "$DDGX" --header "$R"

	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == "docs: matcher precedence"* ]]
}

@test "F1 opens the concise help page from the picker" {
	cat >"$STUB_BIN/tldr" <<'EOF'
#!/usr/bin/env bash
printf 'ddgx picker help\n'
EOF
	chmod +x "$STUB_BIN/tldr"
	stub_ddgr_tripwire

	run env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" \
		bash "$DDGX" --help-page

	[ "$status" -eq 0 ]
	[ "$output" = 'ddgx picker help' ]
	[ "$(grep -Fc -- '--bind="f1:execute($SELF --help-page | less -R)"' "$DDGX")" -eq 1 ]
}

# ---------------------------------------------------------------------------
# One screen. Typing searches, ctrl-f points the same box at the pages already
# found, and enter sends whatever the rows do not answer yet. --typed is the
# change binding, so these drive exactly what a keystroke runs.
# ---------------------------------------------------------------------------

# An empty set, the way a bare start opens the picker.
write_live_state() {
	LIVE="$BATS_TEST_TMPDIR/live.json"
	# A new picker: no query, note or typing mode left over from the last one.
	rm -f "$LIVE".*
	printf '[]\n' >"$LIVE"
	printf 'ddgr\n' >"$LIVE.engine"
}

# The extraction a search starts in the background reaches for every result
# page. Recorded and answered here, so no test fetches one.
stub_node_quiet() {
	cat >"$STUB_BIN/node" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$BATS_TEST_TMPDIR/node.args"
exit 0
EOF
	chmod +x "$STUB_BIN/node"
}

stub_ddgr_counting() {
	cat >"$STUB_BIN/ddgr" <<EOF
#!/usr/bin/env bash
count=0
[ ! -s "$BATS_TEST_TMPDIR/ddgr.count" ] || count=\$(cat "$BATS_TEST_TMPDIR/ddgr.count")
printf '%s\n' "\$((count + 1))" >"$BATS_TEST_TMPDIR/ddgr.count"
printf '%s\n' "\$*" >"$BATS_TEST_TMPDIR/ddgr.args"
printf '%s\n' '$1'
EOF
	chmod +x "$STUB_BIN/ddgr"
}

stub_ask_tripwire() {
	cat >"$STUB_BIN/ask" <<EOF
#!/usr/bin/env bash
touch "$BATS_TEST_TMPDIR/ask.called"
exit 99
EOF
	chmod +x "$STUB_BIN/ask"
}

run_typed() {
	local file=$1
	shift
	run env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" \
		XDG_DATA_HOME="$DATA_HOME" DDGX_DOCS_DIR="${DOCS_DIR:-$BATS_TEST_TMPDIR/no-docs}" \
		DDGX_SUGGEST_DELAY=0 DDGX_ASK_CMD="$STUB_BIN/ask" \
		bash "$DDGX" --typed "$file" 10 "$@"
}

@test "typing a web query searches and becomes the set on screen" {
	write_live_state
	stub_node_quiet
	stub_curl_tripwire
	stub_ddgr_counting '[{"title":"Fresh web result","url":"https://fresh.example/release","abstract":"published now"}]'

	run_typed "$LIVE" 'matcher precedence'

	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 1 ]
	[[ "${lines[0]}" == 0$'\t'*"Fresh web result"* ]]
	[ "$(cat "$LIVE.query")" = 'matcher precedence' ]
	[ "$(cat "$LIVE.engine")" = 'ddgr' ]
	[[ "$(cat "$BATS_TEST_TMPDIR/ddgr.args")" == *'matcher precedence'* ]]
}

@test "typing @ searches the manual, strictly and offline" {
	write_live_state
	write_docs_corpus
	stub_node_quiet
	stub_curl_tripwire
	stub_ddgr_tripwire

	run_typed "$LIVE" '@ "the matcher matches"'

	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == 0$'\t'*"Hooks reference"* ]]
	[ "$(jq -r '.[0].title' "$LIVE")" = 'Hooks reference' ]
	[[ "$output" != *"Agent SDK hooks"* ]]
	[ "$(cat "$LIVE.engine")" = 'docs' ]
	[ "$(cat "$LIVE.query")" = '"the matcher matches"' ]
}

@test "a docs query no page satisfies leaves no partial rows" {
	write_live_state
	write_docs_corpus
	stub_node_quiet
	stub_curl_tripwire
	stub_ddgr_tripwire

	run_typed "$LIVE" '@ matcher precedence zzzznotaword'

	[ "$status" -eq 0 ]
	[ -z "$output" ]
	# The reason rides on the header, not in the list.
	grep -q 'zzzznotaword' "$LIVE.note"
}

@test "live web search waits for typing to pause" {
	write_live_state
	stub_node_quiet
	stub_ddgr_counting '[{"title":"Too soon","url":"https://fresh.example/soon","abstract":"x"}]'

	run timeout 0.1 env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" \
		DDGX_SUGGEST_DELAY=1 bash "$DDGX" --typed "$LIVE" 10 'still typing'

	[ "$status" -eq 124 ]
	[ ! -e "$BATS_TEST_TMPDIR/ddgr.count" ]
}

@test "a short web query waits for more letters" {
	write_live_state
	stub_node_quiet
	stub_ddgr_counting '[]'

	run_typed "$LIVE" 'ku'

	[ "$status" -eq 0 ]
	[ ! -e "$BATS_TEST_TMPDIR/ddgr.count" ]
}

@test "the query the rows already answer costs no search" {
	write_search_state 'kubernetes finalizers'
	stub_node_quiet
	stub_ddgr_counting '[]'

	# Spacing is not part of a query: a trailing space on the way to the next
	# word must not throw the set away.
	run_typed "$RESULTS" ' kubernetes  finalizers '

	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 3 ]
	[[ "${lines[0]}" == *"Finalizers"* ]]
	[ ! -e "$BATS_TEST_TMPDIR/ddgr.count" ]
}

@test "a search typed live is not asked of DuckDuckGo twice" {
	write_live_state
	stub_node_quiet
	stub_ddgr_counting '[{"title":"Fresh once","url":"https://fresh.example/once","abstract":"one request"}]'
	seed_cache 'https://fresh.example/once' 'fresh page body'

	run_typed "$LIVE" 'fresh once'
	[ "$(cat "$BATS_TEST_TMPDIR/ddgr.count")" -eq 1 ]
	run_ddgx -d 'fresh once'

	[ "$status" -eq 0 ]
	[ "$(cat "$BATS_TEST_TMPDIR/ddgr.count")" -eq 1 ]
	[[ "$output" == *"Fresh once"* ]]
}

@test "an expired result set is searched again" {
	write_live_state
	stub_node_quiet
	stub_ddgr_counting '[{"title":"Timed web result","url":"https://fresh.example/timed","abstract":"x"}]'

	env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" \
		DDGX_SEARCH_TTL=1 DDGX_SUGGEST_DELAY=0 \
		bash "$DDGX" --typed "$LIVE" 10 'timed result' >/dev/null
	find "$CACHE_HOME/ddgx/searches" -type f -name '*.json' \
		-exec touch -d '5 minutes ago' {} +
	# A new picker, so the rows on screen do not already answer it.
	write_live_state
	run env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" \
		DDGX_SEARCH_TTL=1 DDGX_SUGGEST_DELAY=0 \
		bash "$DDGX" --typed "$LIVE" 10 'timed result'

	[ "$status" -eq 0 ]
	[ "$(cat "$BATS_TEST_TMPDIR/ddgr.count")" -eq 2 ]
	[[ "$output" == *"Timed web result"* ]]
}

@test "a throttled search keeps the rows and says why on the header" {
	write_search_state 'kubernetes finalizers'
	stub_node_quiet
	cat >"$STUB_BIN/ddgr" <<'EOF'
#!/usr/bin/env bash
echo '[ERROR] HTTP Error 202: Accepted' >&2
printf '[]\n'
EOF
	chmod +x "$STUB_BIN/ddgr"

	run_typed "$RESULTS" 'etcd defrag'

	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 3 ]
	[[ "${lines[0]}" == *"Finalizers"* ]]
	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --header "$RESULTS"
	[[ "${lines[0]}" == *"202"* ]]
	[[ "${lines[0]}" == *"kept the previous results"* ]]
}

@test "a question waits for enter and leaves the rows alone" {
	write_search_state 'kubernetes finalizers'
	write_docs_corpus
	stub_node_quiet
	stub_curl_tripwire
	stub_ddgr_tripwire
	stub_ask_tripwire

	run_typed "$RESULTS" '? matcher precedence'

	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 3 ]
	[ ! -e "$BATS_TEST_TMPDIR/ask.called" ]
	[ "$(cat "$RESULTS.query")" = 'kubernetes finalizers' ]
}

@test "ctrl-f points typing at the pages, and back at the query" {
	write_filter_state
	stub_ddgr_tripwire

	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --toggle "$FR"
	[ "$status" -eq 0 ]
	[[ "$output" == *'change-prompt(in pages > )'* ]]
	[[ "$output" == *'transform-header('* ]]
	[[ "$output" == *'+clear-query' ]]
	[ "$(cat "$FR.typing")" = 'pages' ]

	# The same keystroke binding now filters by page text.
	run_typed "$FR" 'PreToolUse'
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 1 ]
	[[ "${lines[0]}" == *"Hooks reference"* ]]
	[ ! -e "$BATS_TEST_TMPDIR/ddgr.called" ]
	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --header "$FR"
	[[ "${lines[3]}" == *'/ERE/'* ]]

	# Back again: the box gets the set's own query, mark and all.
	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --toggle "$FR"
	[ "$status" -eq 0 ]
	[[ "$output" == *'change-prompt(search > )'* ]]
	[[ "$output" == *'+change-query:@ hooks' ]]
	[ "$(cat "$FR.typing")" = 'web' ]
	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --header "$FR"
	[[ "${lines[3]}" == *'ctrl-f in pages'* ]]
}

@test "the box carries each engine's mark, and the depth an ask was held at" {
	write_ask_state 'etcd defrag'
	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --box "$RESULTS"
	[[ "$output" == *'+change-query:?? etcd defrag' ]]
	# No header here: the reload before it ends in a load that draws one, and
	# a second draw would wipe the note the first one showed.
	[[ "$output" != *'transform-header'* ]]

	printf 'resp_seed\n1\nlow\n' >"$RESULTS.thread"
	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --box "$RESULTS"
	[[ "$output" == *'+change-query:? etcd defrag' ]]

	write_search_state 'kubernetes finalizers site:kubernetes.io'
	printf 'ddgr\n' >"$RESULTS.engine"
	rm -f "$RESULTS.thread"
	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --box "$RESULTS"
	[[ "$output" == *'+change-query:kubernetes finalizers site:kubernetes.io' ]]
}

@test "enter sends a query the rows do not answer yet" {
	write_search_state 'kubernetes finalizers'

	run bash "$DDGX" --enter "$RESULTS" 0 8 '?? why do pods stay terminating'

	[ "$status" -eq 0 ]
	[[ "$output" == *'--submit'* ]]
	[[ "$output" == *'reload('* ]]
	[[ "$output" != 'accept' ]]
	# The query waits in a file: the action is printed for fzf to parse, and a
	# query is free to carry the paren that would end it.
	[ "$(cat "$RESULTS.submit")" = '?? why do pods stay terminating' ]
	[[ "$output" != *'why do pods'* ]]
}

@test "the sent query runs at the depth its mark asked for" {
	write_search_state 'kubernetes finalizers'
	stub_ask "$ASK_REPLY"
	printf '%s' '?? why do pods stay terminating' >"$RESULTS.submit"

	run env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" \
		XDG_DATA_HOME="$DATA_HOME" DDGX_TTL=0 DDGX_ASK_CMD="$STUB_BIN/ask" \
		bash "$DDGX" --submit "$RESULTS" 8

	[ "$status" -eq 0 ]
	[ "$(asked_query)" = 'why do pods stay terminating' ]
	asked_with 'high'
	[ "$(cat "$RESULTS.engine")" = 'pplx' ]
	[ "$(cat "$RESULTS.query")" = 'why do pods stay terminating' ]
	[ ! -e "$RESULTS.submit" ]
}

@test "enter on the query the rows answer opens the row" {
	write_search_state 'kubernetes finalizers'

	run bash "$DDGX" --enter "$RESULTS" 0 8 'kubernetes finalizers'

	[ "$status" -eq 0 ]
	[ "$output" = "accept" ]
}

@test "enter in the page filter opens the row, whatever is typed" {
	write_filter_state
	printf 'pages\n' >"$FR.typing"

	run bash "$DDGX" --enter "$FR" 0 8 'PreToolUse'

	[ "$status" -eq 0 ]
	[ "$output" = "accept" ]
}

@test "enter on an empty list with nothing typed does nothing" {
	write_live_state

	run bash "$DDGX" --enter "$LIVE" '' 8 ''

	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "the query box's words are not marked as page matches" {
	# Before ctrl-f the box holds the query, a question included, and marking
	# its every word would read as a filter that is not running.
	write_two_results
	local r="$BATS_TEST_TMPDIR/results.json" plain
	printf 'first\n' >"$r.query"

	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --preview "$r" 0 ''
	[ "$status" -eq 0 ]
	plain=$output
	[[ "$plain" == *"body of the first page"* ]]

	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --preview "$r" 0 'body'
	[ "$status" -eq 0 ]
	[ "$output" = "$plain" ]

	printf 'pages\n' >"$r.typing"
	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --preview "$r" 0 'body'
	[ "$status" -eq 0 ]
	[ "$output" != "$plain" ]
}

@test "a page the prefetch has not reached is extracted on the alt-h keypress" {
	stub_tmux '%7'
	local r="$BATS_TEST_TMPDIR/cold.json"
	printf '%s\n' '[{"title":"A cold page","url":"https://example.com/cold","abstract":"x"}]' >"$r"
	printf '%%7' >"$r.target"
	cat >"$STUB_BIN/node" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$BATS_TEST_TMPDIR/node.args"
printf 'markdown built on the keypress\n'
EOF
	chmod +x "$STUB_BIN/node"

	run_send "$r" 0

	[ "$status" -eq 0 ]
	[[ "$(cat "$BATS_TEST_TMPDIR/node.args")" == *"--url https://example.com/cold"* ]]
	grep -q 'markdown built on the keypress' "$DATA_HOME/ddgx/notes/a-cold-page.md"
	[ "$output" = "abort" ]
}

@test "a bare start opens the picker on an empty set, with no search" {
	stub_ddgr_tripwire
	stub_curl_tripwire
	stub_tmux
	cat >"$STUB_BIN/fzf" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >"$BATS_TEST_TMPDIR/fzf.args"
cat >"$BATS_TEST_TMPDIR/fzf.stdin"
exit 130
EOF
	chmod +x "$STUB_BIN/fzf"

	# A tty on stdin is what makes a bare start the popup rather than a pipe.
	run script -qec "env PATH='$STUB_BIN:$PATH' XDG_CACHE_HOME='$CACHE_HOME' \
		XDG_DATA_HOME='$DATA_HOME' bash '$DDGX'" /dev/null </dev/null

	[ "$status" -eq 0 ]
	[[ "$output" != *"was called"* ]]
	local args
	args=$(cat "$BATS_TEST_TMPDIR/fzf.args")
	grep -qx -- '--query=' <<<"$args"
	grep -qx -- '--prompt=search > ' <<<"$args"
	[[ "$args" == *'change:reload('*'--typed'* ]]
	[[ "$args" == *'load:transform-header('* ]]
	[[ "$args" == *'ctrl-f:transform('*'--toggle'* ]]
	[[ "$args" == *'type to search'* ]]
	[ ! -s "$BATS_TEST_TMPDIR/fzf.stdin" ]
}

@test "an empty copy is the network's answer, not the query's" {
	# "nothing in the docs mentions hooks" is a lie when no page was ever
	# fetched, and it is the same mistake search_ddgr goes out of its way not
	# to make: blaming the words for a fetch that never landed.
	write_docs_corpus
	rm -rf "${DOCS_DIR:?}/pages"
	cat >"$STUB_BIN/curl" <<'EOF'
#!/usr/bin/env bash
exit 7
EOF
	chmod +x "$STUB_BIN/curl"

	run env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" \
		XDG_DATA_HOME="$DATA_HOME" DDGX_TTL=0 DDGX_DOCS_DIR="$DOCS_DIR" \
		DDGX_NO_NETWORK=1 \
		bash "$DDGX" --docs -d 'matcher precedence'

	[ "$status" -eq 1 ]
	[[ "$output" == *"docs copy is empty"* ]]
	[[ "$output" != *"nothing in the docs mentions"* ]]
}

@test "the background extractor is not attached to the terminal" {
	# prefetch runs the extractor in the background while fzf owns the terminal
	# in raw mode. Sharing the tty is how the picker starts echoing ^[[A instead
	# of moving the selection, and typing stops filtering: two processes on one
	# terminal, and whichever touches its attributes last wins.
	#
	# It only bites while extraction is still running, so a warm cache
	# reproduces it every time and a cold one hides it completely, which is the
	# opposite of the intuition and cost an hour to pin down. Measured in tmux
	# with a warm cache, four trials: without the redirect 2/2 garbled, with it
	# 2/2 clean.
	#
	# This asserts the redirect is present rather than the behaviour, because
	# proving the behaviour needs a pty and a picker to drive, and bats has
	# neither. The comment carries the evidence the assertion cannot.
	run bash -c "sed -n '/^batch_extract()/,/^}/p' '$DDGX'"

	[ "$status" -eq 0 ]
	[[ "$output" == *"</dev/null"* ]]
}

@test "the docs preview marks the terms that put the page on the list" {
	# A reference page runs to a thousand lines. The row's snippet says the page
	# matched; the pane has to say where, or you are searching the page by eye
	# for the words you just typed.
	write_docs_corpus
	stub_curl_tripwire
	R="$BATS_TEST_TMPDIR/hl.json"
	printf '%s\n' '[{"title":"Hooks reference","url":"https://code.claude.com/docs/en/hooks","abstract":"x"}]' >"$R"
	printf 'matcher precedence\n' >"$R.query"
	printf 'docs\n' >"$R.engine"
	seed_cache "https://code.claude.com/docs/en/hooks" \
		"The matcher filters tool calls and precedence runs narrowest first."

	run env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" \
		XDG_DATA_HOME="$DATA_HOME" DDGX_TTL=0 DDGX_DOCS_DIR="$DOCS_DIR" \
		FZF_PREVIEW_COLUMNS=100 bash "$DDGX" --preview "$R" 0 </dev/null

	[ "$status" -eq 0 ]
	# Reverse video on, and turned off with 27 rather than a full reset, which
	# would end whichever colour run the match landed inside.
	[[ "$output" == *$'\033[7m'* ]]
	[[ "$output" == *$'\033[27m'* ]]
}

@test "a web preview is left alone, operators and all" {
	# DuckDuckGo's syntax is not text to look for in the page it returned.
	R="$BATS_TEST_TMPDIR/web.json"
	printf '%s\n' '[{"title":"A page","url":"https://example.com/a","abstract":"x"}]' >"$R"
	printf 'site:example.com matcher\n' >"$R.query"
	printf 'ddgr\n' >"$R.engine"
	seed_cache "https://example.com/a" "The matcher filters tool calls."

	run env PATH="$STUB_BIN:$PATH" XDG_CACHE_HOME="$CACHE_HOME" \
		XDG_DATA_HOME="$DATA_HOME" DDGX_TTL=0 \
		FZF_PREVIEW_COLUMNS=100 bash "$DDGX" --preview "$R" 0 </dev/null

	[ "$status" -eq 0 ]
	[[ "$output" != *$'\033[7m'* ]]
}

@test "a leading dash stays a flag, which is why exclude cannot be offered" {
	# The other half of the same decision, asserted where it is decided rather
	# than only where it is worked around.
	run bash -c "source '$DDGX' >/dev/null 2>&1 || true; query_terms 'hooks -sdk'"

	[ "$status" -eq 0 ]
	[[ "$output" == *'-sdk'* ]]
}

# --------------------------------------------------------------------------
# Typing in the picker
#
# The box searches the page bodies already on disk, not the row fzf drew. The
# rows carry a title and a domain; the answer is in the extract behind them.
# --------------------------------------------------------------------------

# Three results, two of them with a cached page body, one without.
write_filter_state() {
	FR="$BATS_TEST_TMPDIR/filter.json"
	printf '%s\n' '[{"title":"Hooks reference","url":"https://code.claude.com/docs/en/hooks","abstract":"about hooks"},{"title":"Settings","url":"https://code.claude.com/docs/en/settings","abstract":"about settings"},{"title":"Slash commands","url":"https://code.claude.com/docs/en/slash","abstract":"about commands"}]' >"$FR"
	printf 'hooks\n' >"$FR.query"
	printf 'docs\n' >"$FR.engine"
	seed_cache "https://code.claude.com/docs/en/hooks" \
		"the PreToolUse hook fires before a tool runs
matcher Bash"
	seed_cache "https://code.claude.com/docs/en/settings" \
		"settings.json holds permissions"
}

@test "typing searches the page bodies, not the row" {
	write_filter_state

	# "matcher" appears in one page and in no title.
	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --filter "$FR" 'matcher'

	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 1 ]
	[[ "${lines[0]}" == 0* ]]
}

@test "an empty query keeps every result" {
	write_filter_state

	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --filter "$FR" ''

	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 3 ]
}

@test "two words are ANDed across the page, in any order" {
	write_filter_state

	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --filter "$FR" 'matcher tool'

	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 1 ]

	# The same two words, one of them in a page the other is not in, keeps
	# nothing. An OR would have kept two rows here.
	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --filter "$FR" 'matcher permissions'

	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "a quoted phrase has to appear as written" {
	write_filter_state

	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --filter "$FR" '"before a tool"'
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 1 ]

	# The same words, wrong order: as loose terms they would all be found.
	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --filter "$FR" '"tool before a"'
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "a slash-delimited regex searches the page bodies" {
	write_filter_state

	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --filter "$FR" \
		'/PreToolUse.*before/'

	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 1 ]
	[[ "${lines[0]}" == 0* ]]
}

@test "ERE matches one word, a literal space, then any word" {
	write_filter_state

	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --filter "$FR" \
		'/hook \w+/'

	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 1 ]
	[[ "${lines[0]}" == 0* ]]
}

@test "regex metacharacters stay literal without slash delimiters" {
	write_filter_state

	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --filter "$FR" \
		'PreToolUse.*before'

	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "an invalid regex empties the list without printing an error" {
	write_filter_state

	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --filter "$FR" \
		'/[unterminated/'

	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "a page whose body has not landed yet is judged on its row" {
	write_filter_state

	# The third result was never cached. It stays reachable by its title
	# rather than disappearing until the extractor catches up with it.
	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --filter "$FR" 'slash'

	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 1 ]
	[[ "${lines[0]}" == 2* ]]
}

@test "a query nothing carries empties the list rather than failing" {
	write_filter_state

	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --filter "$FR" 'kubernetes'

	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "the rows keep the index the key bindings act on" {
	write_filter_state

	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --filter "$FR" 'settings'

	[ "$status" -eq 0 ]
	# Field one is the result's own index, not its position in the filtered
	# list: enter, ctrl-o and the preview all read it to find the url.
	[[ "${lines[0]}" == 1$'\t'* ]]
}

@test "the preview marks what is typed in the picker, on any engine" {
	write_filter_state
	printf 'ddgr\n' >"$FR.engine"
	printf 'pages\n' >"$FR.typing"

	run env XDG_CACHE_HOME="$CACHE_HOME" DDGX_TTL=0 FZF_PREVIEW_COLUMNS=60 \
		bash "$DDGX" --preview "$FR" 0 'matcher' </dev/null

	[ "$status" -eq 0 ]
	# Reverse video around the word, the same marking the manual's own terms
	# get. A web set gets it too now: the filter kept this page for that word,
	# so the pane has to show where it is.
	[[ "$output" == *$'\033[7mmatcher\033[27m'* ]]
}

@test "the preview marks the text matched by a regex" {
	write_filter_state
	printf 'ddgr\n' >"$FR.engine"
	printf 'pages\n' >"$FR.typing"

	run env XDG_CACHE_HOME="$CACHE_HOME" DDGX_TTL=0 FZF_PREVIEW_COLUMNS=60 \
		bash "$DDGX" --preview "$FR" 0 '/PreToolUse.*before/' </dev/null

	[ "$status" -eq 0 ]
	[[ "$output" == *$'\033[7mPreToolUse hook fires before\033[27m'* ]]
}

@test "an empty filtered set clears the preview without a jq error" {
	write_filter_state

	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --preview "$FR" '' \
		'low priority' </dev/null

	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "the one picker reads typing itself and never matches rows" {
	# fzf's matcher is off and every keystroke goes through one dispatcher,
	# which searches or filters the pages depending on where ctrl-f left the
	# box. A second change binding would mean a second screen.
	run grep -c -F -e '--disabled' -e 'change:reload($SELF --typed' "$DDGX"

	[ "$status" -eq 0 ]
	[ "$output" -eq 2 ]
	[ "$(grep -c -F 'reload($SELF --filter' "$DDGX")" -eq 0 ]
}

@test "the answer row is searched by its text, not by its title" {
	AR="$BATS_TEST_TMPDIR/answer.json"
	printf '%s\n' '[{"title":"perplexity (low)","url":"","abstract":""},{"title":"A source","url":"https://example.com/s","abstract":"x"}]' >"$AR"
	printf 'why do pods stay terminating\n' >"$AR.query"
	printf 'pplx\n' >"$AR.engine"
	printf 'a finalizer on the object blocks deletion\n' >"$AR.answer"

	# "finalizer" is in the answer text and in no title. The answer row is the
	# one row in the set with no page to fall back to and no way to scroll
	# back to it, so it has to be searched where its words actually are.
	run env XDG_CACHE_HOME="$CACHE_HOME" bash "$DDGX" --filter "$AR" 'finalizer'

	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 1 ]
	[[ "${lines[0]}" == 0$'\t'* ]]
}
