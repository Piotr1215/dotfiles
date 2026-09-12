#!/usr/bin/env bash
# PROJECT: cron-manager
#
# Shared read-only view of the crontab for the two renderers (the argos
# cron-status widget and __cron_status_dump.sh). Both used to carry their own
# copy of the line parser and the staleness budget, and the widget's copy had
# lost the overdue check: a wrapped job with a green state file stayed green
# however long ago that state was written. rss_brief at `0 7` had not fired in
# 20 days and read as healthy. One parser, one budget, one verdict.
#
# Source it; nothing runs on load.

# Print one registry row per scheduled job:
#   schedule<TAB>job<TAB>command<TAB>purpose
# Skips blank lines, env assignments, and everything between the
# `# BEGIN remind` / `# END remind` markers, which __reminder.sh owns and the
# reminders applet already renders. Reads `crontab -l`; a test may point
# CRON_REGISTRY_FILE at a fixture instead.
#
# The purpose is what a person reads to know what a job is for without
# opening anything: the comment line directly above the crontab line, so the
# crontab describes itself. A line with no comment falls back to the first
# header comment of the script it runs.
cron_registry() {
    local line schedule cmd job script in_remind=0 comment="" purpose
    while IFS= read -r line; do
        case "$line" in
            '# BEGIN remind'*) in_remind=1; continue ;;
            '# END remind'*) in_remind=0; continue ;;
        esac
        [ "$in_remind" -eq 1 ] && continue
        if [[ -z "$line" ]]; then comment=""; continue; fi
        if [[ "$line" == \#* ]]; then
            # The line touching the job wins; earlier lines are detail.
            comment="${line#\#}"; comment="${comment# }"
            continue
        fi
        [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] && { comment=""; continue; }

        if [[ "$line" == @* ]]; then
            schedule=$(awk '{print $1}' <<<"$line")
            cmd=$(awk '{$1=""; print substr($0,2)}' <<<"$line")
        else
            schedule=$(awk '{print $1, $2, $3, $4, $5}' <<<"$line")
            cmd=$(awk '{for(i=6;i<=NF;i++) printf "%s ", $i; print ""}' <<<"$line")
        fi
        # A wrapped line names its own job; that name is authoritative.
        if [[ "$cmd" == *__cron_run.sh* ]]; then
            job=$(sed -E 's/.*__cron_run\.sh[[:space:]]+([^[:space:]]+).*/\1/' <<<"$cmd")
        else
            script=$(grep -oE '(/[^ ]+)?/[A-Za-z0-9_.-]+\.(sh|py)' <<<"$cmd" | head -1 || true)
            if [ -n "$script" ]; then
                job=$(basename "$script" | sed 's/\.[^.]*$//')
            else
                job=$(basename "$(awk '{for(i=1;i<=NF;i++) if ($i !~ /=/ && $i != "sudo") {print $i; exit}}' <<<"$cmd")")
            fi
            case "$cmd" in
                *--full*) job="${job}-full" ;;
                *--reconcile*) job="${job}-reconcile" ;;
            esac
            [[ "$line" == @reboot* ]] && job="${job}-reboot"
        fi
        [ -n "$job" ] || { comment=""; continue; }
        purpose="$comment"
        [ -n "$purpose" ] || purpose=$(cron_script_purpose "$cmd")
        printf '%s\t%s\t%s\t%s\n' "$schedule" "$job" "$cmd" "$purpose"
        comment=""
    done < <(if [ -n "${CRON_REGISTRY_FILE:-}" ]; then cat "$CRON_REGISTRY_FILE"; else crontab -l 2>/dev/null; fi)
}

# The first descriptive header comment of the script a crontab command runs:
# the last path token after the final `--` (past every wrapper and guard).
# Skips the shebang, PROJECT/shellcheck/banner lines and anything that is not
# a sentence. Empty when nothing usable is there.
cron_script_purpose() {
    local cmd="$1" target
    target="${cmd##*-- }"
    target="${target%% *}"
    target="${target/#\~/$HOME}"
    [ -f "$target" ] || target=$(command -v "$target" 2>/dev/null) || return 0
    [ -f "$target" ] || return 0
    # `|| true`: a script with no such line makes grep exit 1, and under the
    # callers' pipefail that would abort the whole registry.
    { sed -n '2,15p' "$target" 2>/dev/null \
        | grep -aE '^# ?[A-Za-z]' \
        | grep -vE '^# ?(PROJECT|shellcheck|See:|Usage|WHY|=+)' \
        | head -1 | sed -E 's/^# ?//'; } || true
}

# Rough upper bound, in seconds, on how long a job may legitimately go quiet:
# twice its own interval. Only precise enough to separate "ran on schedule"
# from "silently stopped firing". A line guarded by `__cron_every.sh <stamp>
# <seconds>` ticks hourly but runs on the stamp's interval, so the budget is
# the stamp's, not the tick's: the weekly R2R jobs read as 6d overdue on an
# hourly budget otherwise.
cron_expected_interval() {
    local sched="$1" cmd="${2:-}" min hour dom mon dow every
    if [[ "$cmd" == *__cron_every.sh* ]]; then
        every=$(sed -E 's/.*__cron_every\.sh[[:space:]]+[^[:space:]]+[[:space:]]+([0-9]+).*/\1/' <<<"$cmd")
        if [[ "$every" =~ ^[0-9]+$ ]]; then echo $(( every * 2 )); return; fi
    fi
    case "$sched" in
        @reboot) echo 2592000; return ;;
        @daily|@midnight) echo 172800; return ;;
        @hourly) echo 7200; return ;;
        @weekly) echo 1209600; return ;;
        @monthly) echo 5184000; return ;;
    esac
    read -r min hour dom mon dow <<<"$sched"
    if [[ "$min" == */* ]]; then echo $(( ${min#*/} * 60 * 2 )); return; fi
    # Any fixed minute or list of them, every hour: hourly. A list inside a
    # fixed hour or window (`5,35 7-11`) is a daily job and falls through.
    if [[ "$hour" == "*" ]]; then echo 7200; return; fi
    if [[ "$hour" == */* ]]; then echo $(( ${hour#*/} * 3600 * 2 )); return; fi
    if [[ "$dow" != "*" || "$dom" != "*" || "$mon" != "*" ]]; then echo 1209600; return; fi
    echo 172800
}

# True when a run stamped at epoch $1 is older than schedule $2 (and the
# command's own guard, $3) allows.
cron_overdue() {
    local ts="$1" sched="$2" cmd="${3:-}"
    [ -n "$ts" ] || return 1
    [ "$(( $(date +%s) - ts ))" -gt "$(cron_expected_interval "$sched" "$cmd")" ]
}

# True when the wrapper message says the job's own purpose is spent: a
# verificator that has tripped keeps running on schedule and logging
# "already tripped ...; nothing to do". Green would be a lie about relevance.
cron_spent() {
    [[ "$1" == *"already tripped"* ]]
}

# The schedule in words. `21 10 * * 1` is for cron; a person reading a panel
# wants "Mon 10:21". Covers the shapes this crontab uses and falls back to the
# raw expression for anything else, so nothing is ever mistranslated. A
# `__cron_every.sh` guard names the real cadence, since the tick is not it.
cron_human_schedule() {
    local sched="$1" cmd="${2:-}" min hour dom mon dow every out
    if [[ "$cmd" == *__cron_every.sh* ]]; then
        every=$(sed -E 's/.*__cron_every\.sh[[:space:]]+[^[:space:]]+[[:space:]]+([0-9]+).*/\1/' <<<"$cmd")
        case "$every" in
            604800) echo "weekly"; return ;;
            86400) echo "daily"; return ;;
            3600) echo "hourly"; return ;;
            *[!0-9]*|'') ;;
            *) echo "every $(( every / 3600 ))h"; return ;;
        esac
    fi
    case "$sched" in
        @reboot) echo "at boot"; return ;;
        @hourly) echo "hourly"; return ;;
        @daily|@midnight) echo "daily 00:00"; return ;;
        @weekly) echo "weekly"; return ;;
        @monthly) echo "monthly"; return ;;
    esac
    read -r min hour dom mon dow <<<"$sched"
    [ -n "$dow" ] || { echo "$sched"; return; }
    if [[ "$dom" != "*" || "$mon" != "*" ]]; then echo "$sched"; return; fi
    case "$min" in
        '*/'*|*'-'*'/'*) [[ "$hour" == "*" ]] && { echo "every ${min#*/}m"; return; } ;;
    esac
    if [[ "$hour" == "*" ]]; then
        case "$min" in
            *[!0-9,]*) echo "$sched"; return ;;
        esac
        local -a ms; IFS=',' read -ra ms <<<"$min"
        # Evenly spaced minutes are a period, not a list: 4,19,34,49 is 15m.
        if (( ${#ms[@]} >= 3 && 60 / ${#ms[@]} == ms[1] - ms[0] )); then
            echo "every $(( 60 / ${#ms[@]} ))m"; return
        fi
        out=""
        local m; for m in "${ms[@]}"; do out+="${out:+,}:$(printf '%02d' "$m")"; done
        echo "hourly $out"; return
    fi
    if [[ "$hour" == '*/'* && "$min" =~ ^[0-9]+$ ]]; then
        echo "every ${hour#*/}h at :$(printf '%02d' "$min")"; return
    fi
    if [[ "$hour" =~ ^[0-9]+-[0-9]+$ && "$min" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
        # A window: first tick of the first hour to the last tick of the last.
        out="$(printf '%02d:%02d' "${hour%-*}" "${min%%,*}") to $(printf '%02d:%02d' "${hour#*-}" "${min##*,}")"
    elif [[ "$min" =~ ^[0-9]+$ && "$hour" =~ ^[0-9,]+$ ]]; then
        out=""
        local h; IFS=',' read -ra hs <<<"$hour"
        for h in "${hs[@]}"; do out+="${out:+,}$(printf '%02d:%02d' "$h" "$min")"; done
    else
        echo "$sched"; return
    fi
    case "$dow" in
        '*') echo "daily $out" ;;
        0|7|SUN|sun) echo "Sun $out" ;;
        1|MON|mon) echo "Mon $out" ;;
        2|TUE|tue) echo "Tue $out" ;;
        3|WED|wed) echo "Wed $out" ;;
        4|THU|thu) echo "Thu $out" ;;
        5|FRI|fri) echo "Fri $out" ;;
        6|SAT|sat) echo "Sat $out" ;;
        *) echo "$dow $out" ;;
    esac
}
