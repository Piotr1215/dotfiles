#!/usr/bin/env bash
# Print a compact brief of one TaskWarrior task: description, project, tags,
# due, then annotations oldest first, wrapped. Read-only.
#
# WHY: Gordon's handoff tasks keep the brief (what it is, what "yes" does) in
# annotations, and Piotr had no way to read them without asking. Use:
#   __task_brief.sh <uuid-or-prefix>          print the brief
#   __task_brief.sh --popup <token>           open it in a tmux popup (nvim -R,
#                                             readable and copyable); this is
#                                             the plain read-only popup
#   __task_brief.sh --card <token>            a short card for the @task
#                                             instant answer: ref, title, What:,
#                                             the "Your step:" sentence of the
#                                             newest brief: note and its URLs.
#                                             Exit 3 when the task has no what:.
# The newest `what:` note (one or two plain sentences: the thing, why it exists,
# why it is Piotr's) prints as `What:` right under the title. On 26 Oct Piotr
# picked 3b9d with the @task picker and asked "what is this?" again: the brief
# was a log in Gordon's shorthand with no plain sentence saying what it was.
# <token> may be a full uuid, a prefix, `task:<prefix>`, or a whole
# `@"<uuid>|..."` picker token; the first uuid-looking run is used.
# Env (tests): TASK_BRIEF_TASK_COMMAND, TASK_BRIEF_TMUX_COMMAND,
# TASK_BRIEF_WIDTH

set -eo pipefail

mode=plain
case "${1:-}" in
  --popup) mode=popup; shift ;;
  --card) mode=card; shift ;;
esac

token="${1:-}"
if [[ -z "$token" ]]; then
  printf 'usage: %s [--popup|--card] <uuid-or-prefix>\n' "${0##*/}" >&2
  exit 2
fi

# Pull the first hex/dash run of 4+ chars out of whatever was passed.
if [[ "$token" =~ ([0-9a-fA-F][0-9a-fA-F-]{3,35}) ]]; then
  uuid="${BASH_REMATCH[1]}"
else
  printf 'not a task reference: %s\n' "$token" >&2
  exit 2
fi

# Absolute tmux: a hint runs outside the shell that set PATH (see __task_open.sh).
tmux_bin="${TASK_BRIEF_TMUX_COMMAND:-/usr/local/bin/tmux}"
command -v "$tmux_bin" >/dev/null 2>&1 || tmux_bin=tmux
self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/${0##*/}"

if [[ "$mode" == popup ]]; then
  exec "$tmux_bin" display-popup -E -h 80% -w 85% -T " task ${uuid:0:8} " \
    "'$self' '$uuid' | nvim -R -"
fi

task_bin="${TASK_BRIEF_TASK_COMMAND:-task}"
command -v "$task_bin" >/dev/null 2>&1 || {
  printf 'task binary not found\n' >&2
  exit 127
}

tw() {
  "$task_bin" rc.context=none rc.verbose=nothing rc.hooks=off rc.gc=off \
    rc.confirmation=no "$@"
}

# Print the brief of task $1 (full uuid) to stdout.
print_brief() {
  local id="$1" width json
  width="${TASK_BRIEF_WIDTH:-${FZF_PREVIEW_COLUMNS:-${COLUMNS:-80}}}"
  [[ "$width" =~ ^[0-9]+$ ]] || width=80

  json=$(tw "$id" export 2>/dev/null) || json=""
  if ! jq -e 'type == "array" and length > 0' >/dev/null 2>&1 <<<"$json"; then
    printf 'no task matches %s\n' "$id" >&2
    return 1
  fi

  jq -r "$LEAD_JQ"'
    .[0] | lead as $lead |
    "\(.description)\n" +
    (what // "" | if . == "" then "" else "What: \(.)\n" end) +
    ($lead | map(.k + ": " + .v + "\n") | join("")) +
    "uuid:    \(.uuid)\n" +
    "status:  \(.status)" + (if .project then "  project: \(.project)" else "" end) + "\n" +
    (if (.tags // []) | length > 0 then "tags:    \(.tags | join(" "))\n" else "" end) +
    (if .due then "due:     \(.due)\n" else "" end) +
    (if (.annotations // []) | length > 0 then "\nHistory, oldest first:\n" else "" end) +
    ((.annotations // []) | sort_by(.entry)
      | map("\n[\(.entry)]\n\(.description)") | join("\n"))' <<<"$json" |
    fold -s -w "$width"
}

# jq defs for the lead lines, printed above the history so the decision is
# read first (Piotr asked "what this is?" and "what's with 7f?" about handoff
# 7f81 on 23 Oct, whose answer sat in its newest note, below a long first one).
# Sentences of the notes are sorted into: Decided (Piotr's newest answer, "Piotr
# chose A.", "Piotr 11:12: ..."), Effect (what a choice does: the options of the
# newest note that lists them, "A (recommended): ...", or the right side of
# "'<ref> yes' = ..."; after an answer, the rest of that note), Reply (the reply
# he can give, from the newest note that offers one, when newer than his
# answer) and Latest (whatever the newest note says beyond those lines).
LEAD_JQ=$(cat <<'JQ'
  def sents: [splits("(?<=[.?!])\\s+(?=[A-Z0-9'\"(<])")] | map(select(test("\\S")));
  def is_reply: test("^(Reply|Answer)\\b|\\b[Rr]eply\\s+(['\"]|[0-9a-f]{4}\\b)|^Proposal:|^'[^']{1,24}'\\s*[:=]");
  def is_option: test("^(Options?:|[A-D]( \\(recommended\\))?:|\\([a-d]\\)\\s)|\\(recommended\\)");
  def is_decision: (is_reply | not) and test("(?<!to )\\bPiotr( [0-9]{1,2}:[0-9]{2})?( (chose|picked|answered|approved|declined|decided|said)\\b|:)");
  def stamp: (.entry // "") | if length >= 13 then "\(.[4:6])-\(.[6:8]) \(.[9:11]):\(.[11:13])Z " else "" end;
  def what_re: "^\\s*what:\\s*(?=\\S)";
  def is_what: .description | test(what_re; "i");
  # The newest what: note of a task, without its prefix, or null.
  def what: [(.annotations // [])[] | select(is_what)] | sort_by(.entry) | last
    | if . == null then null else .description | sub(what_re; ""; "i") end;
  def lead:
    ((.annotations // []) | map(select(is_what | not)) | sort_by(.entry)
      | map(. + {s: (.description | sents)})) as $a
    | def last_with(f): [range(0; $a | length) as $i | select(any($a[$i].s[]; f)) | $i] | last // -1;
      last_with(is_reply) as $r | last_with(is_option) as $o | last_with(is_decision) as $d
    | (if $d >= 0 then ($a[$d] | stamp) + ($a[$d].s | map(select(is_decision)) | join(" ")) else "" end) as $decided
    | (if $r > $d then $a[$r].s | map(select(is_reply)) else [] end) as $reply
    | (if $r > $d then
         (if $o > $d then $a[$o].s | map(select(is_option))
          else $reply | map(select(test(" = ")) | sub("^.*? = "; "")) end)
       elif $d >= 0 then $a[$d].s | map(select((is_decision or is_reply) | not))
       else [] end) as $effect
    | ($decided + " " + ($effect + $reply | join(" "))) as $shown
    | (if ($a | length) > 0 then
         ($a[-1] | stamp) as $st
         | $a[-1].s | map(select(. as $x | $shown | contains($x) | not)) | join(" ")
         | if . == "" then "" else $st + . end
       else "" end) as $latest
    | [ {k: "Decided", v: $decided}, {k: "Latest", v: $latest},
        {k: "Effect", v: ($effect | join(" "))}, {k: "Reply", v: ($reply | join(" "))} ]
    | map(select(.v != ""));
JQ
)

# Print the instant-answer card of task $1: ref and title, What:, the "Your
# step:" (or "What you decide:") sentence of the newest brief: note, then each
# URL of that note the sentence does not already show. Unwrapped, so URLs stay
# whole. Returns 1 for no task, 3 for a task with no what: note.
print_card() {
  local json out
  json=$(tw "$1" export 2>/dev/null) || json=""
  if ! jq -e 'type == "array" and length > 0' >/dev/null 2>&1 <<<"$json"; then
    printf 'no task matches %s\n' "$1" >&2
    return 1
  fi
  out=$(jq -r "$LEAD_JQ"'
    def urls: [scan("https?://[^\\s<>\"`]+") | sub("[.,;:)\\]]+$"; "")]
      | reduce .[] as $u ([]; if any(.[]; . == $u) then . else . + [$u] end);
    .[0] | what as $what | select($what != null)
    | ([(.annotations // [])[] | select(.description | test("^\\s*brief:"; "i"))]
        | sort_by(.entry) | last | .description // "") as $brief
    | ($brief | sents | map(select(test("(^|\\s)(Your step|What you decide):")))
        | last // "" | sub("^.*?(?=(Your step|What you decide):)"; "")) as $step
    | [ "\(.uuid[0:4])  \(.description)", "What: \($what)",
        (if $step != "" then $step else empty end),
        ($brief | urls[] | select(. as $u | $step | contains($u) | not)) ]
    | join("\n")' <<<"$json")
  [[ -n "$out" ]] || return 3
  printf '%s\n' "$out"
}

if [[ "$mode" == card ]]; then
  rc=0
  print_card "$uuid" || rc=$?
  exit "$rc"
fi

print_brief "$uuid" || exit 1
