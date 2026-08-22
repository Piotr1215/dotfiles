#!/usr/bin/env bash
# PROJECT: cron-manager
#
# Pulsing dot beside the cron-status calendar: shows, live, that a scheduled
# job is running right now. Some jobs here run 10+ minutes, and the main
# widget's own last-run state can't convey "still working" at a 1m refresh.
#
# Deliberately a second widget rather than a badge on cron-status.1m.sh. A
# pulse needs a refresh measured in seconds, and cron-status re-parses the
# whole crontab and computes every next-run time; running that every 2s would
# burn CPU and close the job menu under the cursor on each tick. This one only
# stats the state directory, so it is cheap enough to tick fast.
#
# Sorts before cron-status.1m.sh, so argos places it immediately left of the
# calendar icon. Refresh: 2s (from filename suffix).

set -eo pipefail

STATE_DIR="${CRON_STATE_DIR:-$HOME/.local/state/cron-jobs}"
INVESTIGATE="alacritty -e $HOME/dev/dotfiles/scripts/__cron_investigate.sh"

running=()
if [ -d "$STATE_DIR" ]; then
    for f in "$STATE_DIR"/*.json; do
        [ -f "$f" ] || continue
        read -r state pid < <(jq -r '[.state // "", .pid // ""] | @tsv' "$f" 2>/dev/null || echo "")
        [ "$state" = "running" ] || continue
        # A marker left behind by a run that died is not a running job; without
        # this check the dot would pulse forever after a single crash.
        if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
            continue
        fi
        running+=("$(basename "$f" .json)")
    done
fi

if [ "${#running[@]}" -eq 0 ]; then
    # A lone separator hides the button outright. Argos keeps a widget visible
    # whenever it has no dropdown (button.js: `visible = buttonLines.length > 0
    # || !dropdownMode`), so printing nothing, or an empty line, leaves a dead
    # icon parked next to the calendar. Emitting only `---` puts it in dropdown
    # mode with zero button lines, which is the one combination that hides it.
    echo "---"
    exit 0
fi

# Pulse by cycling opacity rather than swapping glyphs: a changing glyph shifts
# its neighbours by a pixel or two on every tick, which reads as jitter. Alpha
# leaves the layout fixed. Three steps at a 2s refresh is a slow breath, not a
# blink, which is what "work in progress" should look like.
step=$(( ($(date +%s) / 2) % 4 ))
case "$step" in
    0) alpha="100%" ;;
    1) alpha="65%" ;;
    2) alpha="35%" ;;
    3) alpha="65%" ;;
esac

# Bare dot, no count: the bar already carries the calendar's error/hit badge,
# and a second number beside it read as a competing status rather than as
# "something is working". How many, and which, is one click away in the menu.
echo "<span color='#44ff44' alpha='${alpha}'>●</span> | font='monospace' size=11"
echo "---"
echo "Running now (${#running[@]}) | font=monospace"
for job in "${running[@]}"; do
    echo "🟣 ${job#__} | font=monospace bash='${INVESTIGATE} \"${job}\"' terminal=false"
done
