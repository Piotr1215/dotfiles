#!/usr/bin/env bash
# __lib_pane_deliver.sh - put text into the tmux pane a popup was opened from.
#
# Sourced by the popup tools that hand work back to the pane underneath them:
# __orchestrator.sh (M-i, skill invocations) and __ddgx.sh (M-g, search result
# extracts). One copy, because both were solving the same problem and only one
# of them had solved it correctly.
#
# Nothing is ever submitted. The text lands on the pane's input line and the
# human presses Enter. A popup that submits on your behalf submits the wrong
# thing into a live agent, and there is no undo for that.
#
# Two traps live here, both established by probe rather than by reading:
#
# 1. paste-buffer WITHOUT -p replays the buffer as keystrokes, so every newline
#    is an Enter. A three-line payload pasted that way ran as three separate
#    shell commands. -p wraps the paste in bracketed-paste markers, which
#    readline and every terminal UI treat as literal text. This matters the
#    moment a payload can hold more than one line, which is any marked set.
#
# 2. The popup owns the client until its process exits, so a paste issued from
#    inside the popup races the handover and lands in a pane that is still
#    being torn down. run-shell -b defers it past that.
#
# The caller owns its own fallback (clipboard, an error line, whatever fits its
# UI). This library does one thing and reports whether it worked.

# The pane id a popup was opened from. Both bindings in .tmux.conf capture it
# with `set-option -gF @popup_source_pane "#{pane_id}"` before display-popup,
# because a popup cannot read it back out for itself: $TMUX_PANE is EMPTY
# inside a display-popup, and display-popup does not format-expand its
# shell-command, so passing #{pane_id} as an argument delivers the literal
# string. Capturing it in the binding is the only route left.
POPUP_SOURCE_OPTION='@popup_source_pane'

# Resolve the pane to deliver into: explicit argument, then the option the
# binding set. Nothing else.
#
# There is deliberately no $TMUX_PANE fallback. It is empty inside a popup, so
# it can never help the case it looks like it is there for, and outside a popup
# it names the caller's OWN pane. That turns a hand-off run from a shell alias
# into a paste into the terminal you are looking at, reported as a success.
# Returning empty here is what makes the caller say "no source pane" instead.
popup_source_pane() {
	local pane="${1:-}"
	if [[ -z $pane ]] && command -v tmux >/dev/null 2>&1; then
		pane="$(tmux show-option -gqv "$POPUP_SOURCE_OPTION" 2>/dev/null || true)"
	fi
	printf '%s' "$pane"
}

# Test the output, not the exit status: `display-message -t` reports an unknown
# pane by printing nothing and still exiting 0, so branching on the status makes
# the check always true and any fallback unreachable. The paste then fails
# inside a backgrounded run-shell, where nobody sees it, and the payload is lost
# with no error.
pane_is_live() {
	[[ -n "${1:-}" ]] || return 1
	[[ -n "$(tmux display-message -p -t "$1" '#{pane_id}' 2>/dev/null)" ]]
}

# deliver_to_pane <target-pane> <content>
# Returns non-zero when the pane is gone or tmux refuses the buffer, so the
# caller can fall back instead of reporting a success that never happened.
deliver_to_pane() {
	local target="${1:-}" content="${2:-}" buffer
	pane_is_live "$target" || return 1
	[[ -n $content ]] || return 1

	# Buffer name carries the pane and pid so two popups delivering at once
	# cannot consume each other's buffer.
	buffer="pane-deliver-${target#%}-$$"
	printf '%s' "$content" | tmux load-buffer -b "$buffer" - 2>/dev/null || return 1
	tmux run-shell -b "sleep 0.15; tmux paste-buffer -p -b '$buffer' -t '$target' -d" 2>/dev/null || {
		tmux delete-buffer -b "$buffer" 2>/dev/null || true
		return 1
	}
}

# Clear the handover option once consumed, so a later popup opened by some
# other path cannot inherit a stale target.
clear_popup_source_pane() {
	tmux set-option -gu "$POPUP_SOURCE_OPTION" 2>/dev/null || true
}
