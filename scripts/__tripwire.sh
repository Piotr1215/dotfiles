#!/usr/bin/env bash
# Tripwires: watch a news search and act when a new headline meets a condition
# only a model can judge. "Broadcom squeezes VMware partners" has no keyword a
# grep could wait on; classif reads each new headline and answers yes or no.
#
# A wire is a file in ~/.config/tripwire/wires/NAME:
#   query=VMware Broadcom
#   condition=Does this headline report Broadcom squeezing VMware partners or customers?
#   action=notify
# action is notify (the default), dm AGENT (a DM on the agents bus), or any
# shell command, which gets the trip as TRIP_WIRE, TRIP_DATE, TRIP_TITLE and
# TRIP_LINK.
#
#   __tripwire.sh add NAME QUERY CONDITION [ACTION]
#   __tripwire.sh list
#   __tripwire.sh rm NAME
#   __tripwire.sh test QUERY CONDITION    judge the current headlines, keep no state
#   __tripwire.sh run                     every wire once; tripwire.timer runs this
#
# A wire's first run arms it: the headlines already there are recorded and
# nothing trips. After that each new headline is judged once, and only a yes at
# p 0.8 or more trips. A feed or model that fails fires the action once with
# the reason, and once more when the wire works again, so a broken wire is loud
# instead of quiet. With CLASSIF=0 runs do nothing.
set -eo pipefail

wires="${TRIPWIRE_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/tripwire/wires}"
state="${XDG_STATE_HOME:-$HOME/.local/state}/tripwire"
snd="${TRIPWIRE_SND:-$HOME/dev/agents-mcp-server/build/snd.js}"
min_p=0.8

die() {
	echo "tripwire: $*" >&2
	exit 2
}

# The headlines Google News holds for a query, one per line: id, date, title, link.
headlines() {
	local url xml
	url="https://news.google.com/rss/search?q=$(jq -rn --arg q "$1" '$q|@uri')&hl=en-US&gl=US&ceid=US:en"
	xml="$(curl -sf --max-time 20 "$url")" || return 1
	[[ "$xml" == *"<rss"* ]] || return 1
	# One item parses as a map, not a list: wrap and flatten so one or none read the same as many.
	printf '%s' "$xml" |
		yq -p xml -o tsv '[.rss.channel.item] | flatten | .[] | select(. != null) | [.guid."+content", .pubDate, .title, .link]' 2>/dev/null
}

# classif's exit code for one headline against the condition, with today's date as context.
judge() {
	local condition="$1" date="$2" title="$3"
	printf 'Published: %s\nHeadline: %s\n' "$date" "$title" |
		classif -t "$min_p" "$condition" -c <(echo "Today's date:"; date) >/dev/null 2>&1
}

# Fire a wire's action: name, action, date, title, link.
act() {
	local name="$1" action="${2:-notify}" date="$3" title="$4" link="$5"
	case "$action" in
	notify)
		notify-send "tripwire: $name" "$title${link:+
$link}"
		;;
	dm\ *)
		AGENTS_NATS_URL="${AGENTS_NATS_URL:-nats://nats-nats-tailscale.tail165ec.ts.net:4222}" SND_FROM=tripwire \
			node "$snd" -t "${action#dm }" "tripwire $name: $title${link:+ $link}"
		;;
	*)
		TRIP_WIRE="$name" TRIP_DATE="$date" TRIP_TITLE="$title" TRIP_LINK="$link" bash -c "$action" </dev/null
		;;
	esac
}

# One field of a wire file: name, key.
field() {
	local line
	while IFS= read -r line || [[ -n "$line" ]]; do
		[[ "$line" == "$2="* ]] && { printf '%s' "${line#"$2="}"; return 0; }
	done <"$wires/$1"
	return 0
}

# A failing wire acts once with the reason; later failures stay quiet until it works.
broken() {
	local name="$1" why="$2" action="$3"
	echo "tripwire: $name: $why" >&2
	[[ -f "$state/$name.broken" ]] && return 0
	printf '%s\n' "$why" >"$state/$name.broken"
	act "$name" "$action" "$(date -R)" "tripwire $name is broken: $why" "" || true
}

recovered() {
	local name="$1" action="$2"
	[[ -f "$state/$name.broken" ]] || return 0
	rm -f "$state/$name.broken"
	act "$name" "$action" "$(date -R)" "tripwire $name works again" "" || true
}

run_wire() {
	local name="$1" query condition action seen items id date title link rc
	query="$(field "$name" query)" condition="$(field "$name" condition)" action="$(field "$name" action)"
	[[ -n "$query" && -n "$condition" ]] || { broken "$name" "the wire file lacks query= or condition=" "$action"; return 1; }
	seen="$state/$name.seen"
	items="$(headlines "$query")" || { broken "$name" "the news feed did not answer" "$action"; return 1; }
	if [[ ! -f "$seen" ]]; then
		cut -f1 <<<"$items" | sed '/^$/d' >"$seen"
		echo "tripwire: armed $name on $(wc -l <"$seen") headlines" >&2
		recovered "$name" "$action"
		return 0
	fi
	while IFS=$'\t' read -r id date title link; do
		[[ -n "$id" ]] || continue
		grep -qxF "$id" "$seen" && continue
		rc=0
		judge "$condition" "$date" "$title" || rc=$?
		case "$rc" in
		0)
			echo "$id" >>"$seen"
			printf '%s\t%s\t%s\t%s\n' "$name" "$date" "$title" "$link"
			act "$name" "$action" "$date" "$title" "$link" || echo "tripwire: $name: the action failed" >&2
			;;
		1 | 3) echo "$id" >>"$seen" ;;
		*)
			# Unscored: the headline stays unseen, so the next run judges it again.
			broken "$name" "classif could not judge (exit $rc)" "$action"
			return 1
			;;
		esac
	done <<<"$items"
	recovered "$name" "$action"
}

cmd_run() {
	local name failed=0
	if [[ "${CLASSIF:-1}" == 0 ]]; then
		echo "tripwire: classif is off (CLASSIF=0); nothing judged" >&2
		return 0
	fi
	[[ -d "$wires" ]] || return 0
	mkdir -p "$state"
	for name in $(command ls "$wires"); do
		run_wire "$name" || failed=1
	done
	return "$failed"
}

cmd_add() {
	local name="$1" query="$2" condition="$3" action="${4:-notify}"
	[[ "$name" =~ ^[A-Za-z0-9_-]+$ ]] || die "a wire name is letters, digits, - and _"
	[[ -n "$query" && -n "$condition" ]] || die "usage: add NAME QUERY CONDITION [ACTION]"
	[[ ! -e "$wires/$name" ]] || die "$name exists; rm it first"
	mkdir -p "$wires"
	printf 'query=%s\ncondition=%s\naction=%s\n' "$query" "$condition" "$action" >"$wires/$name"
	echo "added $name; its first run arms it"
}

cmd_list() {
	local name status
	[[ -d "$wires" ]] || return 0
	for name in $(command ls "$wires"); do
		if [[ -f "$state/$name.broken" ]]; then
			status="broken: $(<"$state/$name.broken")"
		elif [[ -f "$state/$name.seen" ]]; then
			status="armed, $(wc -l <"$state/$name.seen") seen"
		else
			status="arms on its next run"
		fi
		printf '%s\t%s\t%s\t%s\n' "$name" "$(field "$name" query)" "$(field "$name" action)" "$status"
	done
}

cmd_rm() {
	[[ -e "$wires/$1" ]] || die "no wire named $1"
	rm -f "$wires/$1" "$state/$1.seen" "$state/$1.broken"
	echo "removed $1"
}

cmd_test() {
	local query="$1" condition="$2" items id date title link
	[[ -n "$query" && -n "$condition" ]] || die "usage: test QUERY CONDITION"
	items="$(headlines "$query")" || die "the news feed did not answer"
	while IFS=$'\t' read -r id date title link; do
		[[ -n "$id" ]] || continue
		judge "$condition" "$date" "$title" && printf '%s\t%s\t%s\n' "$date" "$title" "$link"
	done <<<"$items"
	return 0
}

case "${1:-}" in
add) shift && cmd_add "$@" ;;
list) cmd_list ;;
rm) [[ -n "${2:-}" ]] || die "usage: rm NAME" && cmd_rm "$2" ;;
test) shift && cmd_test "$@" ;;
run) cmd_run ;;
*) sed -n '2,24s/^# \{0,1\}//p' "$0" >&2 && exit 2 ;;
esac
