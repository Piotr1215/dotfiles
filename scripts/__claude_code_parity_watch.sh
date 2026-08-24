#!/usr/bin/env bash
# PROJECT: cron-manager
#
# Watches anthropics/claude-code releases for capabilities that narrow the
# gap with the cross-vendor agent framework at ~/dev/agents-mcp-server
# (Claude, Codex, and Gemini share one group there). On a new release, asks a
# sonnet agent to read the live framework source, diff the changelog against
# it, and produce a feature-comparison table, then emails it.
#
# Meant to run through __cron_run.sh, whose exit-code convention this follows:
#   0 no-hit (still on the last-checked release)
#   2 hit    (new release, comparison emailed)
#   else     error
set -eo pipefail
IFS=$'\n\t'

REPO="anthropics/claude-code"
AGENTS_MCP_DIR="${AGENTS_MCP_DIR:-$HOME/dev/agents-mcp-server}"
STATE_FILE="${PARITY_WATCH_STATE:-$HOME/.local/state/claude-code-parity-watch.json}"
RECIPIENT="${PARITY_WATCH_RECIPIENT:-piotrzan@gmail.com}"
MAILER="${PARITY_WATCH_MAILER:-msmtp ${RECIPIENT}}"
# Absolute, because cron's PATH is /usr/{local/,}{s,}bin:/snap/bin and claude is
# in none of them. It used to be reachable, then the 2026-08-23 install moved it
# under ~/.local/bin and every run since exited 127 at the agent call. Point at
# the symlink, not versions/<n>, so a version bump keeps working. Same pin as
# __rss_brief.sh, the other cron job that drives claude.
CLAUDE_BIN="${PARITY_WATCH_CLAUDE_BIN:-$HOME/.local/bin/claude}"

# Everything this script says goes to stdout, which is the only channel
# __cron_run.sh can capture. Print each step before it runs and its result
# after, so the per-job log is readable with tail -f while the job is working
# rather than arriving in one lump when it exits.
log() {
	printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "${*:2}"
}

api() {
	local path="$1" token
	local -a auth=()
	if token="$(gh auth token 2>/dev/null)" && [ -n "$token" ]; then
		auth=(-H "Authorization: Bearer ${token}")
	fi
	curl -fsSL --max-time 30 "${auth[@]}" \
		-H "Accept: application/vnd.github+json" \
		"https://api.github.com/${path}" 2>/dev/null || echo 'null'
}

read_state() {
	[ -f "$STATE_FILE" ] || { echo ""; return 0; }
	jq -r '.last_checked_tag // ""' "$STATE_FILE" 2>/dev/null || echo ""
}

write_state() {
	local tag="$1" tmp
	mkdir -p "$(dirname "$STATE_FILE")"
	tmp="$(mktemp)"
	jq -n --arg t "$tag" --argjson ts "$(date +%s)" \
		'{last_checked_tag: $t, checked_at: $ts}' >"$tmp"
	mv "$tmp" "$STATE_FILE"
}

# msmtp is the fragile link here: under cron it cannot always reach the
# password store, and it reports that only on stderr. Swallowing it meant a
# silently undelivered report. Log what it said and return its real status.
deliver() {
	local subject="$1" kind="$2" merr rc
	merr="$(mktemp)"
	log INFO "delivering ${kind} mail to ${RECIPIENT} via '${MAILER}': ${subject}"
	rc=0
	sh -c "$MAILER" 2>"$merr" || rc=$?
	if [ -s "$merr" ]; then
		log WARN "mailer stderr:"
		sed -e 's/^/    /' "$merr"
	fi
	rm -f "$merr"
	if [ "$rc" -eq 0 ]; then
		log INFO "mailer accepted the message"
	else
		log ERROR "mailer exited ${rc}, report not delivered"
	fi
	return "$rc"
}

send_html_mail() {
	local subject="$1" html_body="$2"
	{
		printf 'Subject: %s\n' "$subject"
		printf 'From: %s\n' "$RECIPIENT"
		printf 'To: %s\n' "$RECIPIENT"
		printf 'MIME-Version: 1.0\n'
		printf 'Content-Type: text/html; charset=UTF-8\n\n'
		printf '%s\n' "$html_body"
	} | deliver "$subject" HTML
}

send_text_mail() {
	local subject="$1" body="$2"
	{
		printf 'Subject: %s\n' "$subject"
		printf 'From: %s\n' "$RECIPIENT"
		printf 'To: %s\n\n' "$RECIPIENT"
		printf '%s\n' "$body"
	} | deliver "$subject" text
}

log INFO "resolving latest ${REPO} release"
latest_tag="$(api "repos/${REPO}/releases/latest" | jq -r '.tag_name // empty')"
if [ -z "$latest_tag" ]; then
	log ERROR "could not resolve latest ${REPO} release (github api unreachable or rate-limited)"
	exit 1
fi

last_tag="$(read_state)"
log INFO "latest=${latest_tag} last_checked=${last_tag:-none} state_file=${STATE_FILE}"

if [ "$latest_tag" = "$last_tag" ]; then
	log INFO "SUMMARY: no-hit: still on ${latest_tag}, nothing to compare"
	exit 0
fi

log INFO "new release, fetching CHANGELOG.md"
changelog="$(curl -fsSL --max-time 30 https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md 2>/dev/null || echo "")"
if [ -z "$changelog" ]; then
	log ERROR "could not fetch CHANGELOG.md from raw.githubusercontent.com"
	exit 1
fi
log INFO "changelog fetched ($(wc -l <<<"$changelog") lines)"

# Delta since the last checked tag, or just the newest entry on a first run.
if [ -n "$last_tag" ]; then
	delta=$(awk -v stop="## ${last_tag#v}" '$0 ~ stop {exit} {print}' <<<"$changelog")
else
	delta=$(awk '/^## /{n++} n<=1{print}' <<<"$changelog")
fi
[ -n "$delta" ] || delta="$changelog"
log INFO "delta since ${last_tag:-none}: $(wc -l <<<"$delta") lines, $(grep -c '^## ' <<<"$delta" || true) release headings"

prompt=$(cat <<PROMPT_EOF
Claude Code just released ${latest_tag} (previously checked: ${last_tag:-none}). Below is the CHANGELOG delta since the last check:

${delta}

Compare this against my cross-vendor multi-agent framework at ${AGENTS_MCP_DIR} (Claude, Codex, and Gemini agents share one group there; tools are register/deregister, discover, dm — 1:1 NATS push, broadcast — group push, channels — channel_send/channel_history/channel_list, log-only bulletin board, groups, and history/backfill via dm_history/group_history/messages_since/poll_messages). Read the actual source there first, do not rely on this description alone.

Filter the changelog delta for anything touching cross-session messaging, agent registration/discovery, hooks-as-transport, or multi-agent coordination (SendMessage, ListAgents, notify_when_idle, crossSessionInbound, etc). If nothing qualifies, say so plainly and stop, do not produce a table.

Otherwise produce a self-contained HTML fragment: one <table> (inline CSS only, no external stylesheet or class references, must render in a plain email client) with columns: Capability | My system | Claude Code native | Parity signal | Adoption readiness. Adoption readiness must be one of: adopt now / wait / keep custom / not applicable.

Adoption stance to apply: my system stays the backbone because it's cross-vendor and supports hook-triggered sends with no agent turn in the loop plus persistent group/channel history, things native messaging can't do. For any row where native looks better for the Claude-only case, add a short note on whether a routing shim makes sense: route to native when running under Claude Code, fall back to my own implementation otherwise. Never recommend a wholesale replacement.

Output ONLY the HTML table fragment (starting with <table and ending with </table>), nothing else: no prose before or after, no markdown fences. If nothing qualified in the filter step, output the single line: NOTHING_RELEVANT
PROMPT_EOF
)

# The agent call is the slow step: it reads a whole repo and takes over a
# minute. `claude --print` alone buffers until it exits, so the log showed a
# header and then nothing for 83 seconds. stream-json emits an event per tool
# call, which this filter turns into one readable line each as they arrive.
# shellcheck disable=SC2016  # jq filter: $e and \(...) are jq syntax, not shell
event_filter='
(try fromjson catch empty) as $e
| if $e.type == "system" and $e.subtype == "init" then
    "  · agent session started (model \($e.model // "?"), \(($e.tools // []) | length) tools)"
  elif $e.type == "assistant" then
    ($e.message.content // [])
    | map(
        if .type == "tool_use" then
          "  · " + .name + "(" + ((.input.file_path // .input.pattern // .input.path // .input.command // "") | tostring | .[0:100]) + ")"
        elif .type == "text" and ((.text // "") | length) > 0 then
          "  · says: " + ((.text | split("\n") | map(select(length > 0)) | .[0] // "") | .[0:120])
        else empty end)
    | .[]
  elif $e.type == "user" then
    ($e.message.content // [])
    | map(if .type == "tool_result" then
            "  · -> " + ((.content | if type == "array" then (map(.text // "") | join(" ")) else (tostring) end) | gsub("\\s+"; " ") | .[0:100])
          else empty end)
    | .[]
  elif $e.type == "result" then
    "  · agent finished: \($e.subtype // "?") in \((($e.duration_ms // 0) / 1000) | floor)s, \($e.num_turns // 0) turns"
  else empty end'

# Checked here rather than at the top: a run that is still on the last-checked
# release exits before this point and never needs the agent, so a missing binary
# must not turn those quiet runs into errors.
if [ ! -x "$CLAUDE_BIN" ]; then
	log ERROR "claude not executable at ${CLAUDE_BIN}; set PARITY_WATCH_CLAUDE_BIN or fix the install"
	exit 1
fi

log INFO "invoking sonnet agent against ${AGENTS_MCP_DIR}; its tool calls stream below"
ev_file="$(mktemp)"
err_file="$(mktemp)"
agent_start=$(date +%s)

set +e
"$CLAUDE_BIN" --print --model claude-sonnet-5 \
	--output-format stream-json --verbose \
	--add-dir "$AGENTS_MCP_DIR" \
	--allowedTools "Read" "Grep" "Glob" \
	-p "$prompt" 2>"$err_file" \
	| tee "$ev_file" \
	| jq -R --unbuffered -r "$event_filter"
claude_rc=${PIPESTATUS[0]}
set -e
agent_dur=$(( $(date +%s) - agent_start ))

if [ -s "$err_file" ]; then
	log WARN "agent wrote to stderr:"
	sed -e 's/^/    /' "$err_file"
fi
[ "$claude_rc" -eq 0 ] || log ERROR "agent exited ${claude_rc} after ${agent_dur}s"

result="$(jq -R -r 'try fromjson catch empty | select(.type == "result") | .result // empty' "$ev_file")"
rm -f "$ev_file" "$err_file"

# An empty result used to fall through and email a report with nothing in it.
# Erroring here is what makes the failure visible on the dashboard instead.
if [ -z "$result" ]; then
	log ERROR "agent produced no result payload after ${agent_dur}s (exit ${claude_rc})"
	exit 1
fi
log INFO "agent returned $(printf '%s' "$result" | wc -c) bytes after ${agent_dur}s"

if printf '%s' "$result" | grep -q "NOTHING_RELEVANT"; then
	log INFO "agent found nothing touching messaging parity; recording ${latest_tag} as checked"
	write_state "$latest_tag"
	# Terminal lines stay bare: the wrapper lifts the last non-blank line
	# verbatim into the dashboard message, so it must read on its own.
	echo "no-hit: ${latest_tag} has nothing relevant to agentic-communication parity"
	exit 0
fi

table_html=$(printf '%s' "$result" | sed -n '/<table/,/<\/table>/p')

if [ -n "$table_html" ]; then
	log INFO "extracted comparison table ($(grep -c '<tr' <<<"$table_html" || true) rows, $(printf '%s' "$table_html" | wc -c) bytes)"
	body="<html><body><p>Claude Code ${latest_tag} vs agents-mcp-server (previously checked: ${last_tag:-none}).</p>${table_html}</body></html>"
	if send_html_mail "Claude Code parity check: ${latest_tag}" "$body"; then
		write_state "$latest_tag"
		echo "hit: emailed HTML comparison for ${latest_tag}"
		exit 2
	fi
	log WARN "HTML delivery failed, falling back to a gist link"
else
	log WARN "agent output contained no <table>; falling back to a gist link"
fi

# HTML path failed or produced nothing usable: fall back to a secret gist link.
gist_url=""
if command -v gh >/dev/null 2>&1; then
	log INFO "creating secret gist with the raw comparison"
	tmp_md="$(mktemp --suffix=.md)"
	printf '# Claude Code %s vs agents-mcp-server\n\n%s\n' "$latest_tag" "$result" >"$tmp_md"
	gist_url="$(gh gist create --secret "$tmp_md" 2>/dev/null || true)"
	rm -f "$tmp_md"
	if [ -n "$gist_url" ]; then
		log INFO "gist created: ${gist_url}"
	else
		log WARN "gh gist create produced no url"
	fi
else
	log WARN "gh not on PATH, no gist fallback available"
fi

summary="Claude Code ${latest_tag} vs agents-mcp-server (previously checked: ${last_tag:-none}). The comparison table didn't render reliably inline."
if [ -n "$gist_url" ]; then
	summary="${summary}
Full comparison: ${gist_url}"
else
	summary="${summary}
Raw agent output follows:

${result}"
fi

if send_text_mail "Claude Code parity check: ${latest_tag}" "$summary"; then
	write_state "$latest_tag"
	echo "hit: emailed fallback summary for ${latest_tag}"
	exit 2
fi

echo "error: could not deliver parity report for ${latest_tag}" >&2
exit 1
