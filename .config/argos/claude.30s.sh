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

if (( bad_count > 0 )); then
    echo "<tt><b>⚠️ C:</b></tt><tt><span color='#ff4444'>$bad_count leaked</span></tt> | font='monospace' size=12 dropdown=false"
elif (( ok_count > 0 )); then
    echo "<tt><b>C:</b></tt><tt><span color='#888888'>${ok_count}</span></tt> | font='monospace' size=12 dropdown=false"
else
    echo "| dropdown=false"
    exit 0
fi

echo "---"

if (( ${#orphan_rows[@]} > 0 )); then
    echo "<b>Orphaned claude (parent gone)</b> | size=11 color=#ff4444"
    for row in "${orphan_rows[@]}"; do
        IFS='|' read -r pid cpu rss etime tty cmd <<< "$row"
        echo "<b>⚠️ PID $pid</b> | color=#ff4444 size=11"
        echo "  CPU: ${cpu}%  Mem: $((rss / 1024))MB  Up: $etime | size=10 color=#888888"
        echo "  ${cmd:0:70} | size=10 color=#888888"
        echo "  Kill -9 | bash='kill -9 $pid' terminal=false refresh=true size=10 color=#ff4444"
    done
    echo "---"
fi

if (( ${#leaked_rows[@]} > 0 )); then
    echo "<b>Leaked prompt monitors (pane closed)</b> | size=11 color=#ff4444"
    for row in "${leaked_rows[@]}"; do
        IFS='|' read -r pid cpu rss etime pane _ <<< "$row"
        echo "<b>⚠️ PID $pid</b> (pane $pane gone) | color=#ff4444 size=11"
        echo "  CPU: ${cpu}%  Mem: $((rss / 1024))MB  Up: $etime | size=10 color=#888888"
        echo "  Kill -9 | bash='kill -9 $pid' terminal=false refresh=true size=10 color=#ff4444"
    done
    echo "---"
fi

if (( ok_count > 0 )); then
    echo "<b>Healthy ($ok_count)</b> | size=11"
    for row in "${claude_rows[@]}"; do
        IFS='|' read -r pid cpu rss etime tty cmd <<< "$row"
        label=$([[ "$tty" == "?" ]] && echo "background" || echo "$tty")
        echo "PID $pid ($label) | size=10"
        echo "  CPU: ${cpu}%  Mem: $((rss / 1024))MB  Up: $etime | size=10 color=#888888"
    done
    echo "---"
fi

if (( bad_count > 0 )); then
    all_bad=("${orphan_pids[@]}" "${leaked_pids[@]}")
    echo "<b>Kill ALL leaked</b> | bash='kill -9 ${all_bad[*]}' terminal=false refresh=true color=#ff4444"
fi
echo "Refresh | refresh=true"
