#!/usr/bin/env bash
# PROJECT: pr-merge
# Shared by the ;;merge and ;;spacelift pickers: the pane on screen, and the
# PRs pr-watch tracks for the agent in it, from any repo, as one list file
# ({"prs":[{"url",plans,applies}]}). pr-watch holds that list in the agent's
# memory, so the sources are what it writes out or draws. First hit wins:
#   1. @pr_watch_export, the file __spawn_agent.sh names on the pane and has
#      pr-watch rewrite through PR_WATCH_EXPORT;
#   2. the live Claude session in the pane: the file pr-watch 0.2.8+ rewrites
#      for every session, $XDG_RUNTIME_DIR/pr-watch/sessions/<session id>.json,
#      else the rows of the pr-watch band on the pane's screen, each a link to
#      its PR, so a session started before either still lists what it shows;
#   3. the live Codex session in the pane: the pr-watch adapter's state file
#      of each thread whose rollout its codex process holds open.
# None of them (a plain shell, no agent): no list, and the pickers do what
# they did before.
#
# Env: PR_PICK_WATCH_FILE names the list file outright (empty: none).
# PR_PICK_CLAUDE_DIRS (Claude config roots), PR_PICK_RUNTIME (where pr-watch
# writes session files), PR_PICK_PROC (/proc), PR_PICK_CACHE (where lists
# built from the band or Codex state are written).

# "<pane id> <directory>" of the active pane in the session the most recently
# used tmux client shows. AutoKey runs outside tmux, and a bare
# `tmux display-message` there resolves the session with the newest activity,
# which is whichever agent printed last, not the one on screen.
focused_pane() {
	tmux list-clients -F '#{client_activity} #{pane_id} #{pane_current_path}' 2>/dev/null |
		sort -rn | head -n1 | cut -d' ' -f2-
}

# The readable pr-watch list file of pane $1, or nothing.
pr_watch_file() {
	local file=""
	if [[ -n "${PR_PICK_WATCH_FILE+x}" ]]; then
		file="$PR_PICK_WATCH_FILE"
	elif [[ -n "${1:-}" ]]; then
		file=$(tmux show-options -pqv -t "$1" @pr_watch_export 2>/dev/null || true)
		[[ -n "$file" && -r "$file" ]] || file=$(session_list "$1" || true)
	fi
	[[ -n "$file" && -r "$file" ]] && printf '%s\n' "$file"
	return 0
}

# The list file of the live Claude or Codex session in pane $1; nothing when
# the pane runs neither or its session tracks no PR.
session_list() {
	local pane="$1" sid runtime="${PR_PICK_RUNTIME:-${XDG_RUNTIME_DIR:-}}" json="" out
	[[ "$pane" =~ ^%[0-9]+$ ]] || return 0
	if sid=$(claude_session "$pane"); then
		if [[ -n "$runtime" && -r "$runtime/pr-watch/sessions/$sid.json" ]]; then
			printf '%s\n' "$runtime/pr-watch/sessions/$sid.json"
			return 0
		fi
		json=$(band_list "$pane")
	else
		json=$(codex_list "$pane")
	fi
	[[ -n "$json" ]] || return 0
	out="${PR_PICK_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/pr-watch}/pick-${pane#%}.json"
	mkdir -p "$(dirname "$out")" && printf '%s\n' "$json" >"$out" && printf '%s\n' "$out"
}

# Session id of the live Claude process in pane $1. Claude Code registers each
# process in <config>/sessions/<pid>.json with its pane as
# "tmux": "<session>:@<window>.<pane>".
claude_session() {
	local dir pid sid
	for dir in ${PR_PICK_CLAUDE_DIRS:-$HOME/.claude-work $HOME/.claude}; do
		compgen -G "$dir/sessions/*.json" >/dev/null || continue
		while read -r pid sid; do
			[[ "$pid" =~ ^[0-9]+$ && "$sid" =~ ^[A-Za-z0-9-]+$ ]] || continue
			kill -0 "$pid" 2>/dev/null || continue
			printf '%s\n' "$sid"
			return 0
		done < <(jq -r --arg p ".$1" 'select((.tmux // "") | endswith($p)) | "\(.pid) \(.sessionId)"' \
			"$dir"/sessions/*.json 2>/dev/null)
	done
	return 1
}

# The PRs a pr-watch band names, from tmux's capture of a screen with its
# escapes: each row opens with its ref (flows#134) linked to the PR, then
# " · ", and links each Spacelift run as "<stack> plan|apply ...". The same
# rows fill the PRs pane of the fullscreen layout.
# shellcheck disable=SC2016 # jq program, not shell
BAND_JQ='
def link: "\u001b\\]8;[^;\u001b]*;";
def st: "\u001b\\\\";
def row: link + "(?<url>https://github\\.com/(?<owner>[A-Za-z0-9_.-]+)/(?<repo>[A-Za-z0-9_.-]+)/pull/(?<n>[0-9]+))" + st
  + "(?<ref>[^\u001b]*)\u001b\\]8;;" + st + " · ";
def run: link + "https://[A-Za-z0-9-]+\\.app\\.spacelift\\.io/stack/(?<stack>[A-Za-z0-9_-]+)/run/[A-Za-z0-9]+" + st
  + "[A-Za-z0-9_-]+ (?<kind>plan|apply) ";
[inputs | gsub("\u001b\\[[0-9;:]*m"; "") as $line
 | first($line | capture(row; "g") | select(.ref == "\(.repo)#\(.n)" or .ref == "\(.owner)/\(.repo)#\(.n)")) as $pr
 | [$line | capture(run; "g")] as $runs
 | {url: $pr.url,
    plans: [$runs[] | select(.kind == "plan") | {stack}],
    applies: [$runs[] | select(.kind == "apply") | {stack}]}]
| reduce .[] as $p ([]; if any(.[]; .url == $p.url) then . else . + [$p] end)
| select(length > 0) | {source: "band", prs: .}'

band_list() {
	tmux capture-pane -p -e -t "$1" 2>/dev/null | jq -Rnc "$BAND_JQ" 2>/dev/null
}

# pids of pane $1's process tree, its shell first.
pane_pids() {
	local root
	root=$(tmux display-message -p -t "$1" '#{pane_pid}' 2>/dev/null) || return 0
	[[ "$root" =~ ^[0-9]+$ ]] || return 0
	ps -e -o pid=,ppid= 2>/dev/null | awk -v root="$root" '
		{ kids[$2] = kids[$2] " " $1 }
		END {
			q[1] = root; n = 1
			for (i = 1; i <= n; i++) { print q[i]; m = split(kids[q[i]], k, " "); for (j = 1; j <= m; j++) q[++n] = k[j] }
		}'
}

# The pr-watch adapter's watched PRs for every Codex thread running in pane
# $1. A codex process holds each thread's <codex home>/sessions/.../
# rollout-<time>-<thread id>.jsonl open, and the adapter keeps the thread's
# state in <codex home>/plugins/data/<marketplace>/<plugin>/<thread id>.json,
# or <codex home>/pr-watch/<thread id>.json without a plugin data directory.
codex_list() {
	local proc="${PR_PICK_PROC:-/proc}" pid link target home state files=()
	local id='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
	while read -r pid; do
		for link in "$proc/$pid"/fd/*; do
			target=$(readlink "$link" 2>/dev/null) || continue
			[[ "$target" =~ ^(/.+)/sessions/.*/rollout-.*-($id)\.jsonl$ ]] || continue
			home=${BASH_REMATCH[1]}
			for state in "$home"/plugins/data/*/*/"${BASH_REMATCH[2]}".json "$home/pr-watch/${BASH_REMATCH[2]}.json"; do
				[[ -r "$state" ]] && files+=("$state")
			done
		done
	done < <(pane_pids "$1")
	((${#files[@]})) || return 0
	jq -sc '[.[] | .watcher.prs | objects | .[]]
		| reduce .[] as $p ([]; if any(.[]; .url == $p.url) then . else . + [$p] end)
		| select(length > 0) | {source: "codex-state", prs: .}' "${files[@]}" 2>/dev/null
}
