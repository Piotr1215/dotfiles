#!/usr/bin/env bash
# PROJECT: spacelift-confirm
# ;;spacelift picker. Lists the Spacelift tracked runs that wait for
# confirmation in rofi, types a confirm command for the pick, and opens the run
# in the browser tiled beside the terminal, the way ;;merge does for PRs.
#
# Typed as one line, no Enter, so nothing applies until you press it:
#   !spacectl stack confirm --id <stack> --run <run> --tail
# The leading ! runs it from a Claude Code prompt; --tail follows the apply.
#
# In an agent pane the runs on stacks its pr-watch PRs plan or apply on come
# first, marked "watched": __lib_pr_watch_export.sh finds that list for Claude
# and Codex panes, from any repo the agent touched.
#
# Usage: __spacelift_confirm_pick.sh [erase]   erase = trigger length to backspace
#
# Env: SPACELIFT_CONFIRM_URL (account URL, default from the current spacectl
# profile), SPACELIFT_CONFIRM_OPEN=0 (no browser), PR_PICK_WATCH_FILE (the
# pr-watch list to rank by; empty for none).
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENER="${SPACELIFT_CONFIRM_OPENER:-xdg-open}"
LAYOUT_SCRIPT="${SPACELIFT_CONFIRM_LAYOUT_SCRIPT:-$SCRIPT_DIR/__layouts.sh}"
LAYOUT="${SPACELIFT_CONFIRM_LAYOUT:-18}"
LAYOUT_DELAY="${SPACELIFT_CONFIRM_LAYOUT_DELAY:-1.5}"
SPACECTL_CONFIG="${SPACECTL_CONFIG:-$HOME/.spacelift/config.json}"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/__lib_rofi_theme.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/__lib_pr_watch_export.sh"

notify() {
	command -v notify-send >/dev/null 2>&1 && notify-send "Spacelift confirm" "$1"
	return 0
}

# Account URL of the current spacectl profile, so the browser opens the same
# account the confirm command talks to.
account_url() {
	if [[ -n "${SPACELIFT_CONFIRM_URL:-}" ]]; then
		printf '%s\n' "${SPACELIFT_CONFIRM_URL%/}"
		return 0
	fi
	jq -r '.profiles[.currentProfileAlias].credentials.endpoint // empty' "$SPACECTL_CONFIG" 2>/dev/null
}

# Ctrl+1's sequence: open, give the browser time to map, tile with focus back
# on the terminal (layout 18). Detached so the picker returns at once.
open_run() {
	[[ "${SPACELIFT_CONFIRM_OPEN:-1}" == "0" || -z "$1" ]] && return 0
	local url="$1" cmd
	# shellcheck disable=SC2016 # expanded by the inner sh
	cmd='"$1" "$2" >/dev/null 2>&1; sleep "$3"; "$4" "$5" >/dev/null 2>&1'
	if [[ "${SPACELIFT_CONFIRM_NO_DETACH:-0}" == "1" ]]; then
		sh -c "$cmd" sh "$OPENER" "$url" "$LAYOUT_DELAY" "$LAYOUT_SCRIPT" "$LAYOUT" </dev/null || true
	else
		setsid -f sh -c "$cmd" sh "$OPENER" "$url" "$LAYOUT_DELAY" "$LAYOUT_SCRIPT" "$LAYOUT" </dev/null >/dev/null 2>&1 || true
	fi
}

# A stack in UNCONFIRMED holds one tracked run waiting for confirmation.
if ! stacks_json=$(spacectl stack list -o json 2>/dev/null); then
	notify "Could not list Spacelift stacks; check spacectl profile login"
	exit 0
fi
mapfile -t stacks < <(jq -r '.[] | select(.state == "UNCONFIRMED") | .id' <<<"$stacks_json")

# One row per waiting run: stack, run, commit, plan counts and title, joined by
# the unit separator so an empty field never collapses into the next one.
# shellcheck disable=SC2016 # jq program, not shell
RUN_JQ='first(.[] | select(.state == "UNCONFIRMED")) // empty
  | [$stack, .id, (.commit.hash // "" | .[0:7]),
     (if .delta then "+\(.delta.addCount) ~\(.delta.changeCount) -\(.delta.deleteCount)" else "plan ?" end),
     (.title // "" | gsub("[\u001f\n]"; " "))] | join("\u001f")'
# Stacks the focused pane's watched PRs plan or apply on.
declare -A watched
watch_file=$(pr_watch_file "$(focused_pane | cut -d' ' -f1)")
if [[ -n "$watch_file" ]]; then
	while read -r s; do
		[[ "$s" =~ ^[A-Za-z0-9_-]+$ ]] && watched[$s]=1
	done < <(jq -r '.prs[]? | (.plans[]?, .applies[]?) | .stack // empty' "$watch_file" 2>/dev/null || true)
fi

# Watched stacks' runs are collected apart and listed first.
ids=() runs=() labels=() w_ids=() w_runs=() w_labels=()
for stack in "${stacks[@]}"; do
	[[ "$stack" =~ ^[A-Za-z0-9_-]+$ ]] || continue
	runs_json=$(spacectl stack run list --id "$stack" --max-results 5 -o json 2>/dev/null) || continue
	row=$(jq -r --arg stack "$stack" "$RUN_JQ" <<<"$runs_json")
	[[ -n "$row" ]] || continue
	IFS=$'\x1f' read -r s r c d t <<<"$row"
	[[ "$r" =~ ^[A-Z0-9]+$ ]] || continue
	if [[ -n "${watched[$s]:-}" ]]; then
		w_ids+=("$s") w_runs+=("$r") w_labels+=("$s  $t  [$d, $c, watched]")
	else
		ids+=("$s") runs+=("$r") labels+=("$s  $t  [$d, $c]")
	fi
done
ids=("${w_ids[@]}" "${ids[@]}") runs=("${w_runs[@]}" "${runs[@]}") labels=("${w_labels[@]}" "${labels[@]}")
if ((${#labels[@]} == 0)); then
	notify "No Spacelift runs wait for confirmation"
	exit 0
fi

rofi_theme 1400
pick=$(printf '%s\n' "${labels[@]}" | rofi -dmenu -i -format i -p "confirm" "${ROFI_THEME[@]}") || exit 0
[[ "$pick" =~ ^[0-9]+$ ]] && ((pick < ${#labels[@]})) || exit 0

# Erase the trigger only now that rofi has closed, so it never races AutoKey.
erase="${1:-0}"
if [[ "$erase" =~ ^[0-9]+$ ]] && ((erase > 0)); then
	backspaces=()
	for ((i = 0; i < erase; i++)); do backspaces+=(BackSpace); done
	xdotool key --clearmodifiers "${backspaces[@]}"
fi

stack=${ids[$pick]} run=${runs[$pick]}
xdotool type --clearmodifiers --delay 12 -- \
	"!spacectl stack confirm --id $stack --run $run --tail"
url=$(account_url || true)
[[ "$url" =~ ^https://[A-Za-z0-9.-]+$ ]] && open_run "$url/stack/$stack/run/$run"
exit 0
