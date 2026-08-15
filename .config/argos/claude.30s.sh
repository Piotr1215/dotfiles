#!/usr/bin/env bash
set -eo pipefail

# Claude process monitor for Argos
# Alert icon only for genuinely leaked processes.
#
# WHY THE OLD TEST WAS WRONG: this used to call a process an orphan when it had
# no controlling TTY ("?"). That was a fair proxy while every claude process was
# a foreground TUI. Claude Code 2.1.232 changed it: agent spawns now run in the
# background by default, so a session carries a supervised set of DETACHED
# helpers (daemon, one bg-pty-host per background session, a pre-warmed spare).
# All of them correctly have no TTY, all have a live parent, and the daemon
# rebuilds any you kill. The old test flagged the whole healthy set every 30s,
# and "Kill ALL orphans" started a fight the daemon always wins.
#
# An orphan is a process whose PARENT IS GONE, so that is what we test: the
# kernel reparents it to pid 1 or to `systemd --user`. Nothing else qualifies.
#
# The second category is the one that actually leaks. __claude_prompt_monitor.sh
# outlives its pane when the pane closes, and it is never named `claude`, so the
# old command match could not see it at all: false alarms on the healthy set,
# silence on the real one. A monitor is leaked when the pane in its environment
# is no longer in `tmux list-panes`.

# PIDs a dead parent reparents to. systemd --user is the subreaper for a user
# session, so a detached helper whose owner died lands there, not on pid 1.
reaper_pids() {
    echo 1
    pgrep -u "$(id -u)" -f 'systemd --user' 2>/dev/null || true
}

mapfile -t REAPERS < <(reaper_pids)

is_reaper() {
    local ppid=$1 r
    for r in "${REAPERS[@]}"; do
        [[ "$ppid" == "$r" ]] && return 0
    done
    return 1
}

# Panes that exist right now, for the leaked-monitor test. Empty when tmux is
# not running, in which case we claim no monitor is leaked rather than guess.
LIVE_PANES=$(tmux list-panes -a -F '#{pane_id}' 2>/dev/null || true)

pane_of() {
    tr '\0' '\n' < "/proc/$1/environ" 2>/dev/null | sed -n 's/^TMUX_PANE=//p' | head -1
}

# pid ppid pcpu rss etime tty command
snapshot() {
    ps -eo pid,ppid,pcpu,rss,etime,tty,args --no-headers 2>/dev/null || true
}

claude_rows=()   # healthy claude processes
orphan_rows=()   # claude processes whose parent died
leaked_rows=()   # prompt monitors whose pane is gone
orphan_pids=()
leaked_pids=()

while read -r pid ppid cpu rss etime tty rest; do
    [[ -z "$pid" ]] && continue

    case "$rest" in
        */claude|claude|*/claude\ *|claude\ *)
            if is_reaper "$ppid"; then
                orphan_rows+=("$pid|$cpu|$rss|$etime|$tty|$rest")
                orphan_pids+=("$pid")
            else
                claude_rows+=("$pid|$cpu|$rss|$etime|$tty|$rest")
            fi
            ;;
        *__claude_prompt_monitor.sh*)
            [[ -z "$LIVE_PANES" ]] && continue
            pane=$(pane_of "$pid")
            [[ -z "$pane" ]] && continue
            if ! grep -qx -- "$pane" <<< "$LIVE_PANES"; then
                leaked_rows+=("$pid|$cpu|$rss|$etime|$pane|monitor")
                leaked_pids+=("$pid")
            fi
            ;;
    esac
done < <(snapshot)

bad_count=$(( ${#orphan_pids[@]} + ${#leaked_pids[@]} ))
ok_count=${#claude_rows[@]}

# NO HEADCOUNT IN THE PANEL. A healthy count is not actionable and it moves on
# its own: the daemon warms and consumes spares, and every TUI that runs a
# background session adds its own set. Showing that number trained the eye to
# read normal churn as a problem, which is how twenty genuine leaks sat
# unnoticed behind four healthy processes wearing a warning icon.
#
# So the panel is binary. Green C means checked, nothing to kill. Red with a
# count means act. The healthy breakdown still exists one click away for the
# rare time it is wanted, but it never competes for attention in the bar.
if (( bad_count == 0 )); then
    if (( ok_count == 0 )); then
        echo "| dropdown=false"
        exit 0
    fi
    # Same markup shape as the other applets in this bar (see hwmon's "T:50C"):
    # a bold <tt> label, then a coloured <tt> value. Pango sizes a label from the
    # glyphs it holds, so a lone letter sits on a different baseline than its
    # neighbours; keeping the label-plus-value pair puts C on their line.
    echo "<tt><b>C:</b></tt><tt><span color='#33d17a'>ok</span></tt> | font='monospace' size=12 dropdown=false"
    echo "---"
    bg=0
    for row in "${claude_rows[@]}"; do
        IFS='|' read -r _ _ _ _ tty _ <<< "$row"
        [[ "$tty" == "?" ]] && (( ++bg ))
    done
    echo "<b>Healthy: $ok_count</b>  ($((ok_count - bg)) tty, $bg background) | size=11 color=#33d17a"
    echo "  background = daemon + bg-pty-hosts + spare (2.1.232+) | size=10 color=#888888"
    echo "---"
    echo "Refresh | refresh=true"
    exit 0
fi

echo "<tt><b>⚠️ C:</b></tt><tt><span color='#ff4444'>$bad_count leaked</span></tt> | font='monospace' size=12 dropdown=false"

echo "---"

# ACTIONS FIRST. The dropdown does not scroll, so anything below roughly a dozen
# lines is unreachable. Listing 20 leaked monitors at three lines each pushed the
# kill button off the bottom, which made the applet useless exactly when it had
# something to report. Details are summarised, never enumerated per PID.
all_bad=("${orphan_pids[@]}" "${leaked_pids[@]}")
echo "<b>⚠️ Kill ALL leaked ($bad_count)</b> | bash='kill -9 ${all_bad[*]}' terminal=false refresh=true color=#ff4444 size=12"
if (( ${#leaked_pids[@]} > 0 && ${#orphan_pids[@]} > 0 )); then
    echo "Kill leaked monitors only (${#leaked_pids[@]}) | bash='kill -9 ${leaked_pids[*]}' terminal=false refresh=true size=11"
    echo "Kill orphaned claude only (${#orphan_pids[@]}) | bash='kill -9 ${orphan_pids[*]}' terminal=false refresh=true size=11"
fi
echo "---"

if (( ${#orphan_rows[@]} > 0 )); then
    echo "<b>Orphaned claude: ${#orphan_rows[@]}</b> (parent gone) | size=11 color=#ff4444"
    printf '%s\n' "${orphan_rows[@]}" | head -4 | while IFS='|' read -r pid _ rss etime _ _; do
        echo "  PID $pid  $((rss / 1024))MB  up $etime | size=10 color=#888888"
    done
    (( ${#orphan_rows[@]} > 4 )) && echo "  and $(( ${#orphan_rows[@]} - 4 )) more | size=10 color=#888888"
fi

if (( ${#leaked_rows[@]} > 0 )); then
    # Cap the pane list: it grows with every closed pane and a long line just
    # makes the dropdown wide for no extra information.
    mapfile -t dead_panes < <(printf '%s\n' "${leaked_rows[@]}" | cut -d'|' -f5 | sort -u)
    panes="${dead_panes[*]:0:6}"
    (( ${#dead_panes[@]} > 6 )) && panes="$panes +$(( ${#dead_panes[@]} - 6 )) more"
    oldest=$(printf '%s\n' "${leaked_rows[@]}" | cut -d'|' -f4 | sort -r | head -1)
    echo "<b>Leaked monitors: ${#leaked_rows[@]}</b> (pane closed) | size=11 color=#ff4444"
    echo "  dead panes: $panes | size=10 color=#888888"
    echo "  oldest up $oldest | size=10 color=#888888"
fi

echo "---"
echo "Refresh | refresh=true"
