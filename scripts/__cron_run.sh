#!/usr/bin/env bash
# PROJECT: cron-manager
# Generic cron wrapper: runs a command, times it, captures its output, and
# writes one JSON status file so cron-manager (the argos widget and the
# tmuxinator dashboard) can show real per-job state instead of guessing from
# log mtimes.
#
# Usage in crontab:
#   M H DoM Mon DoW  /path/__cron_run.sh <job-name> -- <command...>
#
# State is read from the wrapped command's EXIT CODE, chronic-style (silent
# unless there's something to say):
#   0        -> no-hit  (ran clean, nothing notable)
#   2        -> hit     (ran clean, found something worth surfacing)
#   anything else -> error
# A job that wants to report "hit" must exit 2 on that path itself; there is
# no other signal channel. Anything the wrapper can't attribute to the job
# (it crashing before this convention, a shell error) still lands as `error`,
# never silently as `no-hit` — an unrecognized non-zero/non-2 code is `error`.
set -eo pipefail

STATE_DIR="${CRON_STATE_DIR:-$HOME/.local/state/cron-jobs}"
mkdir -p "$STATE_DIR"

job="$1"; shift
if [ "$1" = "--" ]; then shift; fi
if [ -z "$job" ] || [ $# -eq 0 ]; then
    echo "usage: $(basename "$0") <job-name> -- <command...>" >&2
    exit 64
fi

status_file="${STATE_DIR}/${job}.json"
log_file="${STATE_DIR}/${job}.log"

start_ts=$(date +%s)

# Structured run log, same shape as __backup.sh: "[timestamp] [LEVEL] message".
# It is APPENDED, not truncated, and it records the command line and outcome
# rather than only whatever the job chose to print. That distinction is the
# whole point: most jobs here log to a file of their own or say nothing at all,
# so a wrapper that only echoed their stdout left an empty file and no evidence
# the run ever happened. Now a silent job still leaves start/command/exit lines.
wlog() { printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" >>"$log_file"; }

# Rotate so an appended log cannot grow without bound. One previous generation
# is enough to cover "it worked last run, what changed".
if [ -f "$log_file" ] && [ "$(stat -c %s "$log_file" 2>/dev/null || echo 0)" -gt 1048576 ]; then
    mv -f "$log_file" "${log_file}.1"
fi

# Everything below is written before the command runs, so a job that hangs or
# is killed by the nightly shutdown still leaves a record of what it was doing.
# The fields are chosen for what actually root-causes a cron failure:
#
#   caller   cron vs a hand re-run. "works when I run it" is the most common
#            false lead, and this settles it without guessing.
#   resolves the target after symlinks, with its mtime. A crontab line pointing
#            at a stale duplicate of a script is invisible in the command line
#            itself; this is what makes that class of bug legible.
#   PATH     cron's environment is nearly bare, and a tool found interactively
#            but missing under cron is the single most frequent cron-only fault.
if [ -t 0 ]; then caller="interactive"; else caller="cron"; fi
wlog INFO "=== run start: ${job} (pid $$, ${caller})"

# Render the argv so it can be pasted back into a shell verbatim. Plain "$*"
# loses the boundary between arguments, and bare %q backslash-escapes every
# space into something unreadable; quoting only the arguments that actually
# need it keeps the common case clean and the awkward case correct.
fmt_cmd() {
    local a out=""
    for a in "$@"; do
        case "$a" in
            ''|*[!A-Za-z0-9_/.:=@%+-]*)
                out="${out} '$(printf '%s' "$a" | sed "s/'/'\\\\''/g")'" ;;
            *)  out="${out} ${a}" ;;
        esac
    done
    printf '%s' "${out# }"
}
wlog INFO "command: $(fmt_cmd "$@")"

# Resolve the target through symlinks and report its mtime. A crontab line
# pointing at a stale duplicate of a script looks identical to a correct one in
# the command line alone; the resolved path is what exposes it. Builtins and
# non-file targets are named as such rather than being run through readlink,
# which would otherwise invent a bogus path relative to the current directory.
target="$1"
resolved=""
case "$target" in
    */*) [ -e "$target" ] && resolved=$(readlink -f "$target" 2>/dev/null) ;;
    *)   resolved=$(command -v "$target" 2>/dev/null || true)
         case "$resolved" in
             /*) resolved=$(readlink -f "$resolved" 2>/dev/null) ;;
             *)  resolved="" ;;
         esac
         ;;
esac

if [ -n "$resolved" ] && [ -f "$resolved" ]; then
    if [ "$resolved" != "$target" ]; then
        wlog INFO "resolves to: ${resolved} (via ${target}, modified $(date -r "$resolved" '+%Y-%m-%d %H:%M:%S'))"
    else
        wlog INFO "resolves to: ${resolved} (modified $(date -r "$resolved" '+%Y-%m-%d %H:%M:%S'))"
    fi
elif command -v "$target" >/dev/null 2>&1; then
    wlog INFO "resolves to: ${target} (shell builtin or function, no file on disk)"
else
    wlog WARN "resolves to: NOT FOUND -- this run will fail with 127"
fi

# Pre-flight the target's syntax. bash exits 2 on a syntax error, and 2 is this
# wrapper's `hit` code, so a script that is simply broken would otherwise report
# as a green "found something worth surfacing" and be invisible on the board.
# Catching it here turns it into an error before the command is ever run.
if [ -n "$resolved" ] && [ -f "$resolved" ] && head -c2 "$resolved" 2>/dev/null | grep -q '#!'; then
    case "$(head -1 "$resolved")" in
        *bash*|*/sh|*\ sh)
            if ! syn=$(bash -n "$resolved" 2>&1); then
                wlog ERROR "SYNTAX ERROR in ${resolved}, refusing to run:"
                printf '%s\n' "$syn" | sed 's/^/    /' >>"$log_file"
                wlog ERROR "run end: exit=2 state=error duration=0s"
                tmp="$(mktemp)"
                jq -n --arg job "$job" --argjson ts "$(date +%s)" \
                    --arg msg "SYNTAX ERROR: $(printf '%s' "$syn" | head -1)" \
                    --arg lp "$log_file" \
                    '{job: $job, ts: $ts, state: "error", exit_code: 2, duration_s: 0,
                      message: $msg, log_path: $lp}' >"$tmp"
                mv "$tmp" "$status_file"
                printf '%s\n' "$syn" >&2
                exit 2
            fi
            ;;
    esac
fi

# Publish a running marker before handing off, so a job in flight is visible
# rather than looking idle at its last result for however long it takes. The
# PID lets a reader tell a live run from one whose process died without ever
# writing a final state.
running_tmp="$(mktemp)"
jq -n --arg job "$job" --argjson ts "$start_ts" --argjson pid "$$" \
    '{job: $job, ts: $ts, state: "running", pid: $pid}' >"$running_tmp"
mv "$running_tmp" "$status_file"

# Stream the job's output into the log as it is produced, rather than capturing
# it and writing once at the end. Capturing meant a 65-second job showed a
# header and then nothing until it exited, so the log was useless for watching
# work in progress and `tail -f` had nothing to follow. Lines now land as they
# happen, indented so it stays obvious which came from the job and which from
# this wrapper.
#
# sed does the ANSI stripping inline (-u to stay unbuffered, or it would
# reintroduce the very buffering this is removing). PYTHONUNBUFFERED reaches
# the python jobs, which would otherwise block-buffer their stdout into a pipe
# and stream nothing until exit.
wlog INFO "--- output ---"
before=$(wc -l <"$log_file")

export PYTHONUNBUFFERED=1
set +e
"$@" 2>&1 | sed -u -E 's/\x1b\[[0-9;]*[A-Za-z]//g; s/^/    /' >>"$log_file"
code=${PIPESTATUS[0]}
set -e

after=$(wc -l <"$log_file")
end_ts=$(date +%s)
duration=$(( end_ts - start_ts ))

# Say so explicitly. A blank stretch between the banners reads like truncation.
if [ "$after" -eq "$before" ]; then
    printf '    (no output)\n' >>"$log_file"
fi
wlog INFO "--- end output ---"

# `hit` is a deliberate signal from a job that ran. bash reports its own fatal
# faults with the same code 2, so a run whose output carries one of those
# diagnostics is an error however it exited. Without this a broken script paints
# green on the board, which is worse than no signal at all.
bash_fault=0
if [ "$after" -gt "$before" ] && sed -n "$((before + 1)),${after}p" "$log_file" \
        | grep -qE 'syntax error|unexpected (token|end of file)|command not found|: cannot execute'; then
    bash_fault=1
fi

case "$code" in
    0) state="no-hit" ;;
    2) if [ "$bash_fault" -eq 1 ]; then state="error"; else state="hit"; fi ;;
    *) state="error" ;;
esac

# A bare exit code hides the most interesting failure here: this machine powers
# off nightly, so a long job killed mid-run reports 143 and reads like a generic
# error. Naming the signal makes "shut down under me" distinguishable from
# "the job itself failed".
detail=""
if [ "$code" -gt 128 ] && [ "$code" -lt 192 ]; then
    signame=$(kill -l $(( code - 128 )) 2>/dev/null || echo "unknown")
    detail=" (killed by SIG${signame})"
fi

if [ "$state" = "error" ]; then
    # Only on failure, and only here: cron's environment is the usual culprit,
    # but PATH is thousands of characters interactively and would bury every
    # healthy run if it were logged unconditionally.
    wlog ERROR "env: HOME=${HOME} SHELL=${SHELL:-unset} USER=${USER:-unset}"
    wlog ERROR "env: PATH=${PATH}"
    wlog ERROR "run end: exit=${code}${detail} state=${state} duration=${duration}s"
else
    wlog INFO "run end: exit=${code}${detail} state=${state} duration=${duration}s"
fi

# The at-a-glance message: the job's own last meaningful line when it produced
# one, otherwise a statement that it ran, so the dashboard never shows a blank.
last_line=$(sed -n "$((before + 1)),${after}p" "$log_file" \
    | sed 's/^    //' | grep -v '^[[:space:]]*$' | tail -1 || true)
if [ -z "$last_line" ]; then
    last_line="ran, no output (exit ${code}, ${duration}s)"
fi

tmp="$(mktemp)"
jq -n --arg job "$job" --argjson ts "$end_ts" --arg state "$state" \
    --argjson exit_code "$code" --argjson duration "$duration" \
    --arg message "$last_line" --arg log_path "$log_file" \
    '{job: $job, ts: $ts, state: $state, exit_code: $exit_code, duration_s: $duration, message: $message, log_path: $log_path}' \
    > "$tmp"
mv "$tmp" "$status_file"

# Surface output only when there is something to say: an `error` or a `hit`.
# A clean no-hit run stays silent, so cron's mailer is not handed a payload on
# every tick. That matters here because sending fails (msmtp passwordeval
# cannot reach the password store under cron), so every emitted byte becomes a
# failed-delivery line in the journal rather than a mail. The full output is
# still written to $log_file above regardless of state, so nothing goes dark.
if [ "$state" != "no-hit" ]; then
    # Replayed out of the log rather than from a variable: the output is
    # streamed straight to the file now, so this slice is the only copy.
    sed -n "$((before + 1)),${after}p" "$log_file" | sed 's/^    //'
fi
[ "$state" = "error" ] && exit "$code"
exit 0
