#!/usr/bin/env bash
# What the user typed in a Claude Code or Codex session, one message per
# paragraph, without the harness text around it: tool results, reminders,
# skill bodies, a Codex session's instructions and environment. Commands run
# with ! come out as "! command". For piping on: `said | classif "..." -s`.
#
# Usage: said [SESSION_FILE]
#   No file: the session this command runs under, as from a ! command in
#   Claude Code. Else the file, as ;;session types it.
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

file="${1:-}"
if [[ -z "$file" ]]; then
	file=$("$SCRIPT_DIR/__session_paths.sh" --here | head -1)
	file="${file%% | *}"
fi
if [[ -z "$file" ]]; then
	echo "said: not inside a Claude Code or Codex session; pass a session file, e.g. said ;;session" >&2
	exit 1
fi
[[ -f "$file" ]] || { echo "said: no such file: $file" >&2; exit 1; }

if head -1 "$file" | jq -e '.type == "session_meta"' >/dev/null 2>&1; then
	jq -r 'select(.type == "response_item" and .payload.type == "message" and .payload.role == "user")
		| .payload.content[]? | select(.type == "input_text") | .text
		| select((startswith("<") or startswith("# AGENTS.md")) | not)
		| . + "\n"' "$file"
else
	jq -r 'select(.type == "user" and .isMeta != true) | .message.content
		| if type == "string" then .
		  else map(select(.type == "text") | .text | select(startswith("<") | not)) | join("\n") end
		| select(length > 0)
		| if startswith("<bash-input>") then "! " + (sub("^<bash-input>"; "") | sub("</bash-input>\\s*$"; "")) end
		| select((startswith("<")
			or startswith("This session is being continued from a previous conversation")
			or startswith("Here is a note offered by a side agent")) | not)
		| . + "\n"' "$file"
fi | sed '$ { /^$/d }'
