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
	  ctrl-e    the toggle's own editor when registered, else the config
	  esc       back to the launching picker, when there is one
	  ctrl-c    quit everything, including the launching picker

	OPTIONS:
	  --return-marker <file>   touch <file> on a soft exit (esc) so a wrapping
	                           picker knows to restart; ctrl-c leaves no marker

	CONFIG:
	  Plain bash, sourced at startup. Each toggle is registered with:

	    toggle_register "<name>" "<status>" "<on>" "<off>" \
	        ["<description>"] ["<on-label>" "<off-label>"]

	  The three actions are bash function names or single shell commands.
	  The optional description is a short paragraph shown in the preview.
	  Labels rename the two states for display (speak/base, active/disabled);
	  the model underneath stays binary on/off.

	  toggle_edit_action "<name>" "<command>" gives a toggle its own ctrl-e
	  editor (a systemd toggle opens its unit file); default is the conf.
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
declare -A TOGGLE_LABEL_ON=()
declare -A TOGGLE_LABEL_OFF=()
declare -A TOGGLE_EDIT=()

# Results of the last action run. Globals rather than a captured stdout because
# callers need the output and the exit code together.
RUN_OUTPUT=""
RUN_RC=0

# Register a toggle. This is the only API the config file uses. The fifth
# argument is an optional short description shown in the preview panel; the
# sixth and seventh rename the two states for display (speak/base,
# active/disabled). The model underneath stays binary on/off.
toggle_register() {
	local name="$1" status_action="$2" on_action="$3" off_action="$4" desc="${5:-}"
	local label_on="${6:-on}" label_off="${7:-off}"
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
	TOGGLE_LABEL_ON["$name"]="$label_on"
	TOGGLE_LABEL_OFF["$name"]="$label_off"
}

# Optional per-toggle editor for ctrl-e: a command or function name run in
# the popup terminal, so TUIs work. Without one, ctrl-e opens the conf.
toggle_edit_action() {
	local name="$1" action="$2"
	if [[ -z "$name" || -z "$action" ]]; then
		printf 'toggles: toggle_edit_action needs a name and an action\n' >&2
		return 1
	fi
	TOGGLE_EDIT["$name"]="$action"
}

# Ctrl-e: run the highlighted toggle's own editor when registered, otherwise
# open the config.
toggle_edit() {
	local name
	name="$(toggle_name_from_row "${1:-}")"
	if [[ -n "$name" && -n "${TOGGLE_EDIT[$name]:-}" ]]; then
		eval "${TOGGLE_EDIT[$name]}"
	else
		"${EDITOR:-nvim}" "$TOGGLES_CONF"
	fi
}

# Display label for an internal state word. on/off stay the engine's truth;
# labels only change what the board and the preview print.
toggle_label() {
	local name="$1" state="$2"
	case "$state" in
		on) printf '%s\n' "${TOGGLE_LABEL_ON[$name]:-on}" ;;
		off) printf '%s\n' "${TOGGLE_LABEL_OFF[$name]:-off}" ;;
		*) printf '??\n' ;;
	esac
}

# Widest label on the board, so the tag column stays aligned.
toggle_tag_width() {
	local name label width=2
	for name in "${TOGGLE_ORDER[@]}"; do
		for label in "${TOGGLE_LABEL_ON[$name]}" "${TOGGLE_LABEL_OFF[$name]}"; do
			if (( ${#label} > width )); then
				width=${#label}
			fi
		done
	done
	printf '%s\n' "$width"
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
# Tags are label-width, so anything bracketed counts.
toggle_name_from_row() {
	local row="$1"
	if [[ "$row" =~ ^\[[^]]*\][[:space:]](.+)$ ]]; then
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

	local label_from label_to

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
	label_from="$(toggle_label "$name" "$state")"
	label_to="$(toggle_label "$name" "$target")"
	toggle_record "$name" "$label_from" "$label_to" "$action" "$outcome" "$RUN_RC" "$RUN_OUTPUT"
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

# Render the board: one tagged row per registered toggle, tags padded to the
# widest label so the name column lines up.
toggle_render() {
	local name state width
	width="$(toggle_tag_width)"
	for name in "${TOGGLE_ORDER[@]}"; do
		state="$(toggle_state "$name")"
		printf '[%-*s] %s\n' "$width" "$(toggle_label "$name" "$state")" "$name"
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
	if [[ -n "${TOGGLE_DESC[$name]:-}" ]]; then
		printf '\n%s\n' "${TOGGLE_DESC[$name]}"
	fi

	local display="$state"
	if [[ "$state" == on || "$state" == off ]]; then
		display="$(toggle_label "$name" "$state")"
	fi
	printf '\nstate:  %s\n\n' "$display"

	case "$state" in
		on) action="${TOGGLE_OFF[$name]}"; verb="switch to $(toggle_label "$name" off)" ;;
		off) action="${TOGGLE_ON[$name]}"; verb="switch to $(toggle_label "$name" on)" ;;
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
# touches the return marker so a wrapping picker restarts; ctrl-c leaves no
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
		--expect=ctrl-c \
		--prompt 'toggles> ' \
		--header 'enter flip · tab multi · C-r refresh · C-e edit · C-c quit' \
		--preview "'${SELF}' __preview {}" \
		--preview-window 'right:55%:wrap' \
		--bind "enter:execute-silent('${SELF}' __flip {+})+reload('${SELF}' __render)" \
		--bind "ctrl-r:reload('${SELF}' __render)" \
		--bind "ctrl-e:execute('${SELF}' __edit {})+reload('${SELF}' __render)")" || true

	if [[ "${out%%$'\n'*}" == ctrl-c ]]; then
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
	__edit) shift; toggle_edit "${1:-}"; exit 0 ;;
	__run) shift; toggle_exec_action "${1:-}" "${2:-}"; exit $? ;;
esac

toggle_board
