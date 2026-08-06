#!/usr/bin/env bash
set -eo pipefail
IFS=$'\n\t'

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
	cat <<-EOF
	Usage: $(basename "$0") [--help]

	A small fzf board of two-state toggles. Each row shows a state tag and a name:

	  [on ] reading-margin
	  [off] timeoff-mode
	  [?? ] something-unreadable

	KEYS:
	  enter     flip the selected toggle(s), the board stays open and re-renders
	  tab       multi-select, then enter flips all of them
	  ctrl-r    re-read every state
	  ctrl-e    edit the config in nvim
	  esc       quit (back to the launching picker, when there is one)
	  ctrl-x    quit everything, including the launching picker

	OPTIONS:
	  --return-marker <file>   touch <file> on a soft exit (esc) so a wrapping
	                           picker knows to restart; ctrl-x leaves no marker

	CONFIG:
	  Plain bash, sourced at startup. Each toggle is registered with:

	    toggle_register "<name>" "<status>" "<on>" "<off>" ["<description>"]

	  The three actions are bash function names or single shell commands.
	  The optional description is a short paragraph shown in the preview.
	  The status action reports the state through its exit code:
	    0 = on, 1 = off, any other code = unreadable (renders "[?? ]").
	  The on/off actions set that state explicitly, they never blind-flip.
	  A composite action is a function with several steps: it runs them in
	  order and stops at the first failure.

	ENVIRONMENT:
	  TOGGLES_CONF        config file (default: <script dir>/__toggles.conf)
	  TOGGLES_STATE_DIR   last-result files (default: ~/.local/state/toggles)
	EOF
	exit 0
fi

SELF="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SELF")"
: "${TOGGLES_CONF:=${SCRIPT_DIR}/__toggles.conf}"
: "${TOGGLES_STATE_DIR:=${HOME}/.local/state/toggles}"

# Soft exits touch this file so a wrapping picker knows to restart itself.
RETURN_MARKER=""
if [[ "${1:-}" == "--return-marker" ]]; then
	RETURN_MARKER="${2:-}"
	shift 2 || { printf 'toggles: --return-marker needs a path\n' >&2; exit 2; }
fi

# Registry, filled by toggle_register calls from the config file.
TOGGLE_ORDER=()
declare -A TOGGLE_STATUS=()
declare -A TOGGLE_ON=()
declare -A TOGGLE_OFF=()
declare -A TOGGLE_DESC=()

# Results of the last action run. Globals rather than a captured stdout because
# callers need the output and the exit code together.
RUN_OUTPUT=""
RUN_RC=0

# Register a toggle. This is the only API the config file uses. The fifth
# argument is an optional short description shown in the preview panel.
toggle_register() {
	local name="$1" status_action="$2" on_action="$3" off_action="$4" desc="${5:-}"
	if [[ -z "$name" || -z "$status_action" || -z "$on_action" || -z "$off_action" ]]; then
		printf 'toggles: toggle_register needs name, status, on and off actions\n' >&2
		return 1
	fi
	if [[ -n "${TOGGLE_STATUS[$name]:-}" ]]; then
		printf 'toggles: duplicate toggle "%s" in %s\n' "$name" "$TOGGLES_CONF" >&2
		return 1
	fi
	TOGGLE_ORDER+=("$name")
	TOGGLE_STATUS["$name"]="$status_action"
	TOGGLE_ON["$name"]="$on_action"
	TOGGLE_OFF["$name"]="$off_action"
	TOGGLE_DESC["$name"]="$desc"
}

# Read a toggle's status action, capturing combined stdout+stderr into
# RUN_OUTPUT and the exit code into RUN_RC. A nonzero result here is data, not
# a failure, so this one deliberately runs without errexit.
toggle_read_status() {
	local name="$1"
	local restore_errexit=false
	if [[ $- == *e* ]]; then
		restore_errexit=true
	fi
	set +e
	RUN_OUTPUT="$( ( set +e; eval "${TOGGLE_STATUS[$name]}" ) 2>&1 )"
	RUN_RC=$?
	if [[ "$restore_errexit" == true ]]; then
		set -e
	fi
}

# Drive a toggle to a target state, capturing combined stdout+stderr into
# RUN_OUTPUT and the exit code into RUN_RC.
#
# The action runs in a fresh bash process rather than a subshell, and that is
# load-bearing for composites. Bash ignores errexit for the entire dynamic
# extent of a command sitting in a conditional context (an `if`, or a `|| true`
# anywhere up the call chain), and the suppression reaches inside subshells even
# when they `set -e` themselves: the composite would sail past its failing step
# and report success. A separate process starts from a clean slate, so "stop at
# the first failure" holds no matter how a caller wraps this.
toggle_apply() {
	local name="$1" target="$2"
	local restore_errexit=false
	if [[ $- == *e* ]]; then
		restore_errexit=true
	fi
	set +e
	RUN_OUTPUT="$("$SELF" __run "$name" "$target" 2>&1)"
	RUN_RC=$?
	if [[ "$restore_errexit" == true ]]; then
		set -e
	fi
}

# Body of the __run subcommand: execute one action with errexit on, so a
# composite stops at its first failing step and exits with that step's code.
toggle_exec_action() {
	local name="$1" target="$2" action
	if [[ -z "${TOGGLE_STATUS[$name]:-}" ]]; then
		printf 'toggles: unknown toggle "%s"\n' "$name" >&2
		return 1
	fi
	if [[ "$target" == on ]]; then
		action="${TOGGLE_ON[$name]}"
	else
		action="${TOGGLE_OFF[$name]}"
	fi
	set -e
	eval "$action"
}

# Translate a status action's exit code into a state word.
toggle_state_word() {
	case "$1" in
		0) printf 'on\n' ;;
		1) printf 'off\n' ;;
		*) printf 'unknown\n' ;;
	esac
}

# Read one toggle's current state, printing on, off or unknown.
toggle_state() {
	local name="$1"
	toggle_read_status "$name"
	toggle_state_word "$RUN_RC"
}

# Path of the file holding a toggle's last flip result.
toggle_state_file() {
	local safe="${1//[^A-Za-z0-9_-]/_}"
	printf '%s/%s.last\n' "$TOGGLES_STATE_DIR" "$safe"
}

# Strip the "[on ] " tag so fzf can pass a board row through untouched.
toggle_name_from_row() {
	local row="$1"
	if [[ "$row" =~ ^\[.{3}\][[:space:]](.+)$ ]]; then
		printf '%s\n' "${BASH_REMATCH[1]}"
	else
		printf '%s\n' "$row"
	fi
}

# Write the last-result file the preview panel reads back.
toggle_record() {
	local name="$1" from="$2" to="$3" action="$4" outcome="$5" rc="$6" output="$7"
	local file
	file="$(toggle_state_file "$name")"
	{
		printf '%s  flip %s: %s -> %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$name" "$from" "$to"
		printf 'action: %s\n' "$action"
		if [[ "$outcome" == refused ]]; then
			printf 'outcome: refused, state unreadable so nothing was run\n'
		else
			printf 'outcome: %s (exit %s)\n' "$outcome" "$rc"
		fi
		printf 'output:\n'
		if [[ -n "$output" ]]; then
			printf '%s\n' "$output" | tail -n 20 | sed 's/^/  /'
		else
			printf '  (none)\n'
		fi
	} >"$file"
}

# Flip one toggle: read its state, then run the opposite state's action.
toggle_flip() {
	local name="$1"
	if [[ -z "${TOGGLE_STATUS[$name]:-}" ]]; then
		printf 'toggles: unknown toggle "%s"\n' "$name" >&2
		return 1
	fi

	local state target action outcome
	toggle_read_status "$name"
	state="$(toggle_state_word "$RUN_RC")"

	# Without a readable state there is no defined opposite, so refuse rather
	# than guess which way to drive it.
	if [[ "$state" == unknown ]]; then
		toggle_record "$name" unknown "-" "${TOGGLE_STATUS[$name]}" refused "$RUN_RC" "$RUN_OUTPUT"
		return 0
	fi

	if [[ "$state" == on ]]; then
		target=off
		action="${TOGGLE_OFF[$name]}"
	else
		target=on
		action="${TOGGLE_ON[$name]}"
	fi

	toggle_apply "$name" "$target"
	outcome=ok
	if (( RUN_RC != 0 )); then
		outcome=failed
	fi
	toggle_record "$name" "$state" "$target" "$action" "$outcome" "$RUN_RC" "$RUN_OUTPUT"
	return 0
}

# Flip every named toggle, one independent of the next. Unknown names are
# filtered here rather than wrapping the flip in `|| true`, which would put the
# action in an errexit-ignored context, see toggle_apply.
toggle_flip_many() {
	local row name
	for row in "$@"; do
		name="$(toggle_name_from_row "$row")"
		if [[ -z "$name" ]]; then
			continue
		fi
		if [[ -z "${TOGGLE_STATUS[$name]:-}" ]]; then
			printf 'toggles: unknown toggle "%s"\n' "$name" >&2
			continue
		fi
		toggle_flip "$name"
	done
}

# Render the board: one tagged row per registered toggle.
toggle_render() {
	local name state tag
	for name in "${TOGGLE_ORDER[@]}"; do
		state="$(toggle_state "$name")"
		case "$state" in
			on) tag='[on ]' ;;
			off) tag='[off]' ;;
			*) tag='[?? ]' ;;
		esac
		printf '%s %s\n' "$tag" "$name"
	done
}

# Read-only detail panel: current state, what enter would run, last result.
toggle_preview() {
	local name state action verb reason file
	name="$(toggle_name_from_row "$1")"
	if [[ -z "$name" ]]; then
		return 0
	fi
	if [[ -z "${TOGGLE_STATUS[$name]:-}" ]]; then
		printf 'unknown toggle: %s\n' "$name"
		return 0
	fi

	toggle_read_status "$name"
	state="$(toggle_state_word "$RUN_RC")"
	reason="$RUN_OUTPUT"

	printf 'toggle: %s\n' "$name"
	printf 'state:  %s\n\n' "$state"

	if [[ -n "${TOGGLE_DESC[$name]:-}" ]]; then
		printf '%s\n\n' "${TOGGLE_DESC[$name]}"
	fi

	case "$state" in
		on) action="${TOGGLE_OFF[$name]}"; verb='turn it off' ;;
		off) action="${TOGGLE_ON[$name]}"; verb='turn it on' ;;
		*) action=''; verb='' ;;
	esac

	if [[ -z "$action" ]]; then
		printf 'enter:  refuses, the state cannot be read (status exit %s)\n' "$RUN_RC"
		if [[ -n "$reason" ]]; then
			printf 'reason: %s\n' "$reason"
		fi
	else
		printf 'enter:  runs %s to %s\n\n' "$action" "$verb"
		printf 'action:\n'
		if declare -F "$action" >/dev/null 2>&1; then
			declare -f "$action"
		else
			printf '%s\n' "$action"
		fi
	fi

	printf '\nlast result:\n'
	file="$(toggle_state_file "$name")"
	if [[ -f "$file" ]]; then
		cat "$file"
	else
		printf '(nothing run yet)\n'
	fi
}

# The board itself. Flips happen in a child process so fzf stays open, then the
# list reloads so the tags reflect what just happened. Esc is a soft exit that
# touches the return marker so a wrapping picker restarts; ctrl-x leaves no
# marker, so the whole popup chain quits.
toggle_board() {
	local list out
	list="$(toggle_render)"
	if [[ -z "$list" ]]; then
		printf 'toggles: no toggles registered in %s\n' "$TOGGLES_CONF" >&2
		exit 1
	fi

	out="$(printf '%s\n' "$list" | fzf \
		--multi \
		--reverse \
		--expect=ctrl-x \
		--prompt 'toggles> ' \
		--header 'enter: flip   tab: multi-select   ctrl-r: refresh   ctrl-e: edit config   esc: back   ctrl-x: exit all' \
		--preview "'${SELF}' __preview {}" \
		--preview-window 'right:55%:wrap' \
		--bind "enter:execute-silent('${SELF}' __flip {+})+reload('${SELF}' __render)" \
		--bind "ctrl-r:reload('${SELF}' __render)" \
		--bind "ctrl-e:execute(nvim '${TOGGLES_CONF}')+reload('${SELF}' __render)" \
		--bind 'ctrl-c:abort')" || true

	if [[ "${out%%$'\n'*}" == ctrl-x ]]; then
		return 0
	fi
	if [[ -n "$RETURN_MARKER" ]]; then
		touch "$RETURN_MARKER"
	fi
}

if [[ ! -f "$TOGGLES_CONF" ]]; then
	printf 'toggles: config not found: %s\n' "$TOGGLES_CONF" >&2
	exit 1
fi
# shellcheck source=/dev/null
source "$TOGGLES_CONF"

mkdir -p "$TOGGLES_STATE_DIR"

# Child processes (fzf bindings, and the __run action runner) must resolve the
# same config and state dir this instance did
export TOGGLES_CONF TOGGLES_STATE_DIR

# Hidden subcommands this script re-invokes itself with
case "${1:-}" in
	__render) toggle_render; exit 0 ;;
	__flip) shift; toggle_flip_many "$@"; exit 0 ;;
	__preview) shift; toggle_preview "${1:-}"; exit 0 ;;
	__run) shift; toggle_exec_action "${1:-}" "${2:-}"; exit $? ;;
esac

toggle_board
