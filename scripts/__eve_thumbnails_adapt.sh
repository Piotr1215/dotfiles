#!/usr/bin/env bash
set -eo pipefail

# PROJECT: eve
# Recompute eve-preview-manager thumbnail positions for the screens attached
# right now.
#
# EPM stores one absolute X11 rectangle per character in config.json and
# rewrites that file itself on exit and on every drag, so positions saved on
# the single 4k desk at home (a row of four 450x253 previews along the top
# right) land off-screen or on the wrong screen on the laptop desk. Each
# character keeps a slot number in a sidecar file this script owns; the slot's
# rectangle is computed fresh for the current screens:
#
#   one screen        a row along the top right of the main screen, the
#                     geometry the home desk has always used
#   a second screen   a two column grid filling the secondary (laptop) panel,
#                     leaving the main screen to the client being played
#
# Run before EPM starts. EPM writes the file on exit, so a rewrite while it
# runs is lost; the script refuses unless --force is given.
#
#   --print   show the plan, write nothing
#   --force   write even while EPM is running

source "$(dirname "${BASH_SOURCE[0]}")/__lib_screen.sh"

CONFIG="${EVE_PREVIEW_CONFIG:-$HOME/.config/eve-preview-manager/config.json}"
SLOTS="${EVE_PREVIEW_SLOTS:-${CONFIG%/*}/thumbnail-slots.tsv}"

# The home row: 450x253 previews, 9px below the top edge, 49px in from the
# right edge. Kept as the single screen layout so home does not move.
ROW_W="${EVE_THUMB_W:-450}"
ROW_H="${EVE_THUMB_H:-253}"
ROW_TOP=9
ROW_RIGHT_MARGIN=49
GRID_COLS=2

# Print "name<TAB>x<TAB>y" for every character whose thumbnail has been
# placed by hand. A character still at the profile's default size was never
# placed (a character that logged in once and was left at the drop point),
# and stays where it is.
placed_thumbnails() {
	jq -r '.profiles[0] as $p
		| $p.character_thumbnails // {}
		| to_entries[]
		| select(.value.width != $p.thumbnail_default_width
			or .value.height != $p.thumbnail_default_height)
		| [.key, .value.x, .value.y] | @tsv' "$CONFIG"
}

# Print "name<TAB>slot". The sidecar is created from the current positions the
# first time (distinct positions ranked top to bottom, left to right; two
# characters at one position share the slot, which is how the home row keeps
# alts stacked) and gains a line for each newly placed character after that.
ensure_slots() {
	local name x y next pos slot
	declare -A slot_of=() pos_slot=()
	if [[ -f "$SLOTS" ]]; then
		while IFS=$'\t' read -r name slot; do
			[[ -n "$name" ]] && slot_of["$name"]="$slot"
		done <"$SLOTS"
	fi
	next=0
	for slot in "${slot_of[@]}"; do (( slot >= next )) && next=$((slot + 1)); done
	while IFS=$'\t' read -r name x y; do
		[[ -n "$name" && -z "${slot_of[$name]:-}" ]] || continue
		pos="$y,$x"
		if [[ -z "${pos_slot[$pos]:-}" ]]; then
			pos_slot["$pos"]=$next
			next=$((next + 1))
		fi
		slot_of["$name"]="${pos_slot[$pos]}"
		printf '%s\t%s\n' "$name" "${slot_of[$name]}" >>"$SLOTS.new"
	done < <(placed_thumbnails | sort -t $'\t' -k3,3n -k2,2n)
	if [[ -f "$SLOTS.new" ]]; then
		cat "$SLOTS.new" >>"$SLOTS"
		rm -f "$SLOTS.new"
	fi
	[[ -f "$SLOTS" ]] && cat "$SLOTS"
	return 0
}

# Print "x y w h" for slot $1 of $2 on the main screen: the home row, shrunk
# only when the screen is too narrow to hold every slot at full size.
row_geometry() {
	local i="$1" n="$2" mon geom mw mx my w h
	mon=$(get_target_monitor)
	geom="${mon#* }"
	mw="${geom%%x*}"; geom="${geom#*x}"; geom="${geom#*+}"
	mx="${geom%%+*}"; my="${geom#*+}"
	w=$ROW_W
	(( n * w + ROW_RIGHT_MARGIN > mw )) && w=$(( (mw - ROW_RIGHT_MARGIN) / n ))
	h=$(( w * ROW_H / ROW_W ))
	printf '%s %s %s %s\n' "$(( mx + mw - ROW_RIGHT_MARGIN - (n - i) * w ))" "$(( my + ROW_TOP ))" "$w" "$h"
}

# Print "x y w h" for slot $1 of $2 on the secondary screen: a GRID_COLS wide
# grid of equal cells, starting below the panel if the panel is on that
# screen, scaled down if the rows would run off the bottom.
grid_geometry() {
	local i="$1" n="$2" mon geom mw mh mx my wy rows w h top
	mon=$(get_secondary_monitor)
	geom="${mon#* }"
	mw="${geom%%x*}"; geom="${geom#*x}"
	mh="${geom%%+*}"; geom="${geom#*+}"
	mx="${geom%%+*}"; my="${geom#*+}"
	IFS=' ' read -r _ wy _ _ < <(get_net_workarea)
	top=$my
	[[ -n "${wy:-}" ]] && (( wy > top )) && top=$wy
	rows=$(( (n + GRID_COLS - 1) / GRID_COLS ))
	w=$(( mw / GRID_COLS ))
	h=$(( w * ROW_H / ROW_W ))
	if (( rows * h > my + mh - top )); then
		h=$(( (my + mh - top) / rows ))
		w=$(( h * ROW_W / ROW_H ))
	fi
	printf '%s %s %s %s\n' "$(( mx + (i % GRID_COLS) * w ))" "$(( top + (i / GRID_COLS) * h ))" "$w" "$h"
}

# Print "name<TAB>x<TAB>y<TAB>w<TAB>h" for every slotted character.
plan() {
	local layout=row n=0 name slot slots
	slots=$(ensure_slots)
	[[ -n "$slots" ]] || return 0
	n=$(( $(cut -f2 <<<"$slots" | sort -n | tail -n 1) + 1 ))
	get_secondary_monitor >/dev/null 2>&1 && layout=grid
	while IFS=$'\t' read -r name slot; do
		[[ -n "$name" ]] || continue
		printf '%s\t%s\n' "$name" "$("${layout}_geometry" "$slot" "$n" | tr ' ' '\t')"
	done <<<"$slots"
}

# Write the planned rectangles into config.json, touching nothing else.
apply() {
	local geometry tmp
	geometry=$(plan | jq -R -s 'split("\n") | map(select(length > 0) | split("\t"))
		| map({key: .[0], value: {x: (.[1]|tonumber), y: (.[2]|tonumber),
			width: (.[3]|tonumber), height: (.[4]|tonumber)}}) | from_entries')
	[[ "$geometry" != "{}" ]] || return 0
	tmp=$(mktemp "${CONFIG}.XXXXXX")
	jq --argjson g "$geometry" '.profiles[0].character_thumbnails |= with_entries(
		if $g[.key] then .value += $g[.key] else . end)' "$CONFIG" >"$tmp"
	# The home desk is the 99 percent case and its row is already right, so
	# leave the file alone (mtime included) unless a rectangle changed.
	if jq -e --slurpfile new "$tmp" '. == $new[0]' "$CONFIG" >/dev/null; then
		rm -f "$tmp"
		return 0
	fi
	mv "$tmp" "$CONFIG"
}

main() {
	local mode=apply force=0 arg
	for arg in "$@"; do
		case "$arg" in
		--print) mode=print ;;
		--force) force=1 ;;
		*) echo "usage: $0 [--print] [--force]" >&2; exit 2 ;;
		esac
	done
	[[ -f "$CONFIG" ]] || { echo "no config at $CONFIG" >&2; exit 1; }
	if [[ "$mode" == print ]]; then
		plan
		return 0
	fi
	if (( ! force )) && pgrep -x eve-preview-man >/dev/null 2>&1; then
		echo "eve-preview-manager is running and would overwrite the file on exit; stop it or pass --force" >&2
		exit 1
	fi
	apply
}

main "$@"
