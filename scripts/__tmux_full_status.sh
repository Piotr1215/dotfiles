#!/usr/bin/env bash
# PROJECT: tmux-status
# Show the status bar's content in full, untruncated, with provenance.
#
# The bar is lossy by design: every source is capped, and tmux then hard-cuts
# status-right from the right at status-right-length, which eats the clock
# before it eats the text. So the one line on screen cannot tell you whether
# you are seeing all of a short goal or the first 116 characters of a long one.
# This prints the whole of each source, says which one won, and says how much
# the bar dropped.
#
# Deliberately does NOT source __tmux_active_task.sh. An inspector that shares
# its reads with the writer it inspects cannot reveal the writer's bugs: both
# would be wrong in the same direction and agree with each other.
set -eo pipefail

CACHE_DIR="${TMUX_TASK_CACHE_DIR:-/tmp/tmux_task_status}"

# --wait holds the popup open. It lives here rather than in the binding because
# display-popup runs its command under default-shell, which is zsh, and zsh's
# read has no -n: `read -rsn1` in the binding died with "bad option: -1" before
# the popup had finished drawing. Inside the script the bash shebang applies.
wait_for_key=0
args=()
for a in "$@"; do
    if [ "$a" = "--wait" ]; then wait_for_key=1; else args+=("$a"); fi
done

session="${args[0]:-$(tmux display-message -p '#S' 2>/dev/null || echo default)}"
pane="${args[1]:-$(tmux display-message -p '#{pane_id}' 2>/dev/null || echo '')}"

# Width comes from the terminal, not from a guess. `tput cols` reports 80 when
# stdout is a pipe, which is exactly why this writes to the popup's tty instead
# of paging: the pane is ~294 columns and wrapping at 80 throws most of it away.
cols="${COLUMNS:-}"
if [ -z "$cols" ] && [ -t 1 ]; then cols=$(tput cols 2>/dev/null) || cols=""; fi
case "$cols" in ''|*[!0-9]*) cols=100 ;; esac

b=$'\033[1m'; dim=$'\033[2m'; off=$'\033[0m'
hdr() { printf '\n%s%s%s\n' "$b" "$1" "$off"; }

# Wrap long values so a 400-char goal does not run off the popup.
wrap() { printf '%s\n' "$1" | fold -s -w "$(( cols - 6 ))" | sed 's/^/      /'; }

# A source row: mark, label, provenance, and how much the bar kept.
row() {
    local won="$1" label="$2" prov="$3" cap="$4" text="$5"
    local mark="[ ]" note
    [ "$won" = "1" ] && mark="[x]"
    if [ -z "$text" ]; then
        note="${dim}empty${off}"
    elif [ "$cap" -gt 0 ] && [ "${#text}" -gt "$cap" ]; then
        note="${#text} chars, bar shows $cap"
    else
        note="${#text} chars, shown in full"
    fi
    printf '  %s %-8s %-22s %s\n' "$mark" "$label" "$prov" "$note"
    # `if`, not `[ ... ] && wrap`. A trailing && list returns 1 when the test is
    # false, and under set -e that kills the script on the first empty source.
    if [ -n "$text" ]; then wrap "$text"; fi
}

# --- what the bar is actually showing right now ---------------------------
limit=$(tmux show-options -gqv status-right-length 2>/dev/null) || limit=""
case "$limit" in ''|*[!0-9]*) limit=100 ;; esac
budget=$(( limit - 24 ))
if [ "$budget" -lt 20 ]; then budget=20; fi

cache_file="$CACHE_DIR/${session//\//-}"
rendered=""
if [ -f "$cache_file" ]; then rendered=$(cat "$cache_file" 2>/dev/null) || rendered=""; fi

printf '%sFULL STATUS%s  session %s   pane %s\n' "$b" "$off" "$session" "${pane:-?}"

hdr "RENDERED NOW"
if [ -n "$rendered" ]; then
    wrap "$rendered"
    printf '  %sline is %s chars; tmux hard-cuts status-right at %s%s\n' \
        "$dim" "${#rendered}" "$limit" "$off"
    if [ "${#rendered}" -gt "$limit" ]; then
        printf '  %s>> %s chars are being cut off the right, clock first%s\n' \
            "$b" "$(( ${#rendered} - limit ))" "$off"
    fi
else
    printf '  %sno cache entry at %s; the bar is showing the date fallback%s\n' \
        "$dim" "$cache_file" "$off"
fi

# --- the sources, untruncated, in the writer's precedence order -----------
hdr "SOURCES  first non-empty wins   (__tmux_active_task.sh)"

pr_title=""
if [[ "$session" =~ -pr-([0-9]+) ]] && command -v gh >/dev/null 2>&1; then
    pr_num="${BASH_REMATCH[1]}"
    pr_title=$(gh pr view "$pr_num" --json title --jq '.title' 2>/dev/null) || pr_title=""
fi

linear_desc=""
if command -v task >/dev/null 2>&1 && [[ "$session" =~ ([a-zA-Z]+-[0-9]+) ]]; then
    lid=$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]')
    linear_desc=$(task rc.verbose=nothing "linear_issue_id:$lid" export 2>/dev/null \
        | jq -r '.[0].description // empty' 2>/dev/null) || linear_desc=""
fi

agent_desc=$(tmux show-options -qv -t "$session" @agent_desc 2>/dev/null) || agent_desc=""
goal=$(tmux display-message -p -t "$session" '#{@claude_goal}' 2>/dev/null) || goal=""

won_pr=0 won_lin=0 won_desc=0 won_goal=0
if   [ -n "$pr_title" ];    then won_pr=1
elif [ -n "$linear_desc" ]; then won_lin=1
elif [ -n "$agent_desc" ];  then won_desc=1
elif [ -n "$goal" ];        then won_goal=1
fi

row "$won_pr"   "pr"     "get_pr_desc :37"     60         "$pr_title"
row "$won_lin"  "linear" "get_agent_issue :64" 0          "$linear_desc"
row "$won_desc" "desc"   "get_agent_desc :80"  60         "$agent_desc"
row "$won_goal" "goal"   "get_claude_goal :99" "$budget"  "$goal"

if [ "$((won_pr + won_lin + won_desc + won_goal))" -eq 0 ]; then
    printf '  %severy source empty, so the bar falls through to date | mode%s\n' "$dim" "$off"
fi

# --- pane border, a separate producer entirely ----------------------------
hdr "PANE BORDER  (__claude_pane_label.sh, hooks write these per pane)"
for opt in @claude_state @claude_glyph @claude_label @claude_label_at; do
    val=$(tmux display-message -p ${pane:+-t "$pane"} "#{$opt}" 2>/dev/null) || val=""
    printf '  %-18s %s\n' "$opt" "${val:-${dim}unset${off}}"
done

if [ "$wait_for_key" = "1" ]; then
    printf '\n  %spress any key%s ' "$dim" "$off"
    # `|| true` because read returns non-zero at EOF, which set -e would treat
    # as a failure when stdin is not a terminal.
    read -rsn1 _ || true
    printf '\n'
fi
