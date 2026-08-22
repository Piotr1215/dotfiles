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

send_html_mail() {
	local subject="$1" html_body="$2"
	{
		printf 'Subject: %s\n' "$subject"
		printf 'From: %s\n' "$RECIPIENT"
		printf 'To: %s\n' "$RECIPIENT"
		printf 'MIME-Version: 1.0\n'
		printf 'Content-Type: text/html; charset=UTF-8\n\n'
		printf '%s\n' "$html_body"
	} | sh -c "$MAILER"
}

send_text_mail() {
	local subject="$1" body="$2"
	{
		printf 'Subject: %s\n' "$subject"
		printf 'From: %s\n' "$RECIPIENT"
		printf 'To: %s\n\n' "$RECIPIENT"
		printf '%s\n' "$body"
	} | sh -c "$MAILER"
}

latest_tag="$(api "repos/${REPO}/releases/latest" | jq -r '.tag_name // empty')"
if [ -z "$latest_tag" ]; then
	echo "could not resolve latest ${REPO} release" >&2
	exit 1
fi

last_tag="$(read_state)"

if [ "$latest_tag" = "$last_tag" ]; then
	echo "no-hit: still on ${latest_tag}"
	exit 0
fi

changelog="$(curl -fsSL --max-time 30 https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md 2>/dev/null || echo "")"
if [ -z "$changelog" ]; then
	echo "could not fetch CHANGELOG.md" >&2
	exit 1
fi

# Delta since the last checked tag, or just the newest entry on a first run.
if [ -n "$last_tag" ]; then
	delta=$(awk -v stop="## ${last_tag#v}" '$0 ~ stop {exit} {print}' <<<"$changelog")
else
	delta=$(awk '/^## /{n++} n<=1{print}' <<<"$changelog")
fi
[ -n "$delta" ] || delta="$changelog"

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

result="$(command claude --print --model claude-sonnet-5 \
	--add-dir "$AGENTS_MCP_DIR" \
	--allowedTools "Read" "Grep" "Glob" \
	-p "$prompt" 2>/tmp/claude-code-parity-watch-debug.log || true)"

if printf '%s' "$result" | grep -q "NOTHING_RELEVANT"; then
	write_state "$latest_tag"
	echo "no-hit: ${latest_tag} has nothing relevant to agentic-communication parity"
	exit 0
fi

table_html=$(printf '%s' "$result" | sed -n '/<table/,/<\/table>/p')

if [ -n "$table_html" ]; then
	body="<html><body><p>Claude Code ${latest_tag} vs agents-mcp-server (previously checked: ${last_tag:-none}).</p>${table_html}</body></html>"
	if send_html_mail "Claude Code parity check: ${latest_tag}" "$body"; then
		write_state "$latest_tag"
		echo "hit: emailed HTML comparison for ${latest_tag}"
		exit 2
	fi
fi

# HTML path failed or produced nothing usable: fall back to a secret gist link.
gist_url=""
if command -v gh >/dev/null 2>&1; then
	tmp_md="$(mktemp --suffix=.md)"
	printf '# Claude Code %s vs agents-mcp-server\n\n%s\n' "$latest_tag" "$result" >"$tmp_md"
	gist_url="$(gh gist create --secret "$tmp_md" 2>/dev/null || true)"
	rm -f "$tmp_md"
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
