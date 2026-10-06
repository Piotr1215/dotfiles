#!/usr/bin/env bash
# Ask Jev, TypeSafe's System One model, one typed question about some input.
# Jev is not a chat model: it answers a question with a number or a pick.
#
# Usage: jev QUESTION [INPUT]                 probability the answer is yes
#        jev -c a,b,c QUESTION [INPUT]        pick one option, with confidence
#        jev -s low,mid,high QUESTION [INPUT] position on ordered levels
#        ... | jev QUESTION                   INPUT read from stdin
#        -j                                   print the raw JSON response
#
# Examples:
#   kubectl describe pod x | jev "did this pod run out of memory?"
#   git log -1 --format=%B | jev -c feature,fix,docs,chore "what kind of change is this?"
#   jev -s "can wait,this week,today" "how urgent is this?" "prod is down for one customer"
#
# The key comes from TYPESAFE_API_KEY, else from pass work/JEV_API_KEY. It is
# handed to curl through a file descriptor, so it never appears in argv.

set -eo pipefail

url="${JEV_URL:-https://api.typesafe.ai/v1/systemone}"

die() {
	echo "jev: $*" >&2
	exit 1
}

usage() {
	sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
	exit "${1:-0}"
}

main() {
	local kind=noul options="" raw="" opt question input key body response
	while getopts ':c:s:jh' opt; do
		case "$opt" in
		c) kind=choice options="$OPTARG" ;;
		s) kind=score options="$OPTARG" ;;
		j) raw=1 ;;
		h) usage 0 ;;
		:) die "-$OPTARG needs a comma-separated list" ;;
		*) die "unknown option -$OPTARG" ;;
		esac
	done
	shift $((OPTIND - 1))

	question="$1"
	[[ -n "$question" ]] || usage 1 >&2
	if [[ $# -ge 2 ]]; then
		input="$2"
	elif [[ ! -t 0 ]]; then
		input=$(cat)
	fi
	[[ -n "$input" ]] || die "nothing to judge: pass INPUT or pipe it in"

	key="${TYPESAFE_API_KEY:-$(pass show work/JEV_API_KEY 2>/dev/null | head -1)}"
	[[ -n "$key" ]] || die "no key: set TYPESAFE_API_KEY or store it in pass work/JEV_API_KEY"

	body=$(jq -n --arg k "$kind" --arg q "$question" --arg i "$input" --arg o "$options" '
		($o | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(. != ""))) as $opts
		| {model: "jev-latest", state: {input: $i},
		   questions: {q: ({type: $k, instructions: ("About `input`: " + $q)}
		     + (if $k == "choice" then {criteria: ($opts | map({key: ., value: null}) | from_entries)}
		        elif $k == "score" then {criteria: $opts}
		        else {} end))}}')
	if [[ "$kind" != noul ]] && [[ $(jq '.questions.q.criteria | length' <<<"$body") -lt 2 ]]; then
		die "-c and -s need at least two options"
	fi

	response=$(curl -sS --max-time 30 "$url" \
		-H @<(printf 'Authorization: Bearer %s\n' "$key") \
		-H 'Content-Type: application/json' -d @- <<<"$body") || die "request failed"

	if [[ -n "$raw" ]]; then
		printf '%s\n' "$response"
		return
	fi
	jq -e '.answers.q' >/dev/null 2>&1 <<<"$response" || die "no answer: $(jq -c '.detail // .' <<<"$response" 2>/dev/null || printf '%s' "$response")"

	# noul: probability. choice: the pick and its confidence. score: position
	# and the nearest level's name.
	jq -r --arg k "$kind" --argjson b "$body" '.answers.q as $a
		| if $k == "noul" then ($a.noul * 100 | round / 100 | tostring)
		  elif $k == "choice" then "\($a.choice) \($a.confidence * 100 | round / 100)"
		  else "\($a.score * 100 | round / 100) \($b.questions.q.criteria[$a.score | round])" end' <<<"$response"
}

main "$@"
