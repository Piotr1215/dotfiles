#!/usr/bin/env bash
set -eo pipefail

# The YubiKey's OATH accounts as a panel badge, and the two signals the secret
# picker sends here instead of sending notifications: a red flashing T while age
# blocks waiting for the key to be touched, and a yellow flash once the value is
# on the clipboard.
#
# Why one second when the count changes maybe twice a year: the blink has to
# start when the copy lands, and argos re-reads a script only on that script's
# own interval. Nothing can poke a single applet from outside. The one external
# trigger argos offers is a change in ~/.config/argos, which tears down and
# re-runs EVERY applet including the weather and github fetches, so it is not
# usable as a nudge.
#
# ykman drives the USB key and takes ~0.5s, far too long for a one second tick
# and a poll that would sit on the key while age or gpg wants it. The count is
# served from a cache that a detached refresh rewrites every 30s, so the key is
# touched exactly as often as it was when this applet ran at 30s.

STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}"
CACHE="$STATE_DIR/argos-totp-accounts"
BLINK="$STATE_DIR/secret-picker-blink"
TOUCH="$STATE_DIR/secret-picker-touch"
CACHE_TTL=30

# Four seconds, which is four flashes: each tick of this applet is one of them
# (see the two-line output below).
BLINK_SECONDS=4

# The tap cue has no duration of its own, it ends when age returns. This is only
# the ceiling for a picker that died without clearing its marker (a killed rofi,
# a kill -9), past which a stuck T would sit in the panel claiming the key is
# waiting for a touch nobody is going to give it.
TOUCH_MAX=120

now=$(date +%s)

mtime_of() { stat -c %Y "$1" 2>/dev/null || echo 0; }

if [ ! -f "$CACHE" ]; then
    # First tick after login has nothing to serve, so pay the 0.5s once.
    ykman oath accounts list >"$CACHE" 2>/dev/null || : >"$CACHE"
elif [ "$((now - $(mtime_of "$CACHE")))" -ge "$CACHE_TTL" ]; then
    # Claim the window before forking, or every tick inside the same second
    # spawns its own ykman.
    touch "$CACHE"
    # setsid with both streams closed: argos reads this script's stdout to EOF,
    # so a child still holding it would keep the panel waiting on ykman anyway.
    setsid bash -c "ykman oath accounts list >'$CACHE.new' 2>/dev/null && mv '$CACHE.new' '$CACHE' || rm -f '$CACHE.new'" \
        >/dev/null 2>&1 </dev/null &
fi

accounts=$(grep -v '^[[:space:]]*$' "$CACHE" 2>/dev/null || true)
count=0
[ -n "$accounts" ] && count=$(printf '%s\n' "$accounts" | wc -l)

# A marker counts only inside its window. Left to age, it would have the panel
# reporting a copy or a pending tap from some earlier session forever.
marker_live() {
    local file="$1" window="$2" age
    [ -f "$file" ] || return 1
    age=$((now - $(mtime_of "$file")))
    if [ "$age" -ge 0 ] && [ "$age" -lt "$window" ]; then
        return 0
    fi
    rm -f "$file"
    return 1
}

state="resting"
if marker_live "$TOUCH" "$TOUCH_MAX"; then
    state="touch"
elif marker_live "$BLINK" "$BLINK_SECONDS"; then
    state="copied"
fi

# $1 = glyph, already carrying its own colour, $2 = colour for the count.
badge() {
    printf "<tt><b>%s:</b></tt><tt><span color='%s'>%s</span></tt> | font='monospace' size=12" "$1" "$2" "$count"
}

# $1 = colour for the whole label. T for touch, so the glyph is a letter and one
# colour has to carry both halves of it.
#
# The leading `<tt> </tt>` is load-bearing. Whatever the panel does to a line's
# first top-level markup element, that element's attributes are dropped: the
# colour on `<tt><span color=..>T</span></tt><tt>..` painted the T in the panel's
# own white while the identical span on the count two elements later came out
# exactly #ff3b30. Screenshotted and sampled pixel by pixel, three phrasings,
# including one span wrapped around the whole label, which lost the colour too.
# An empty `<tt></tt>` does not absorb it, so the sacrificial element has to
# carry a character. The space it costs is the width the key emoji has when the
# badge is resting, so nothing in the panel shifts on the way in or out.
#
# This is the same quirk cron-status.1m.sh worked around by reaching for
# self-colouring emoji. A letter has no such option.
touch_badge() {
    printf "<tt> </tt><tt><span color='%s'><b>T</b>:%s</span></tt> | font='monospace' size=12" "$1" "$count"
}

resting_colour='#44ff44'
[ "$count" -eq 0 ] && resting_colour='#666666'

# Neither signal is drawn by this script. A script emits one frame per run and
# argos will not run one more often than once a second, far too slow to read as
# a flash. Two button lines start argos's own line cycler instead (button.js,
# patched locally to 800ms), so inside each one second tick the panel holds the
# first line for 800ms and the second for the ~200ms left before the next run
# resets the cycle. One tick is one flash.
#
# Self-colouring emoji rather than a <span color=...> around them: a span colour
# on an emoji renders as the panel theme's white, verified by screenshotting the
# bar (same finding as cron-status.1m.sh). `dropdown=false` keeps the cycle lines
# out of the menu, which argos would otherwise prepend the account list with.
case "$state" in
touch)
    # T for touch, and it flashes for the reason the notification it replaced
    # existed: a still glyph in the corner of a 4K panel is exactly what gets
    # forgotten while age sits there blocking on the key. Red, not the copy's
    # yellow, because this one is asking for something.
    echo "$(touch_badge '#ff3b30') dropdown=false"
    echo "$(touch_badge '#3a0000') dropdown=false"
    ;;
copied)
    # Bright yellow against black rather than against the resting key: the key
    # and the flash are both mid-tone glyphs and swapping one for the other read
    # as a wobble rather than a blink. Flash first, so the copy is acknowledged
    # on the tick rather than 800ms into it.
    echo "$(badge "🟡" '#ffdd00') dropdown=false"
    echo "$(badge "⚫" '#222222') dropdown=false"
    ;;
*)
    echo "$(badge "🔑" "$resting_colour")"
    ;;
esac

if [ "$count" -eq 0 ]; then
    echo "---"
    echo "No TOTP accounts on YubiKey"
else
    echo "---"
    echo "$accounts" | while read -r account; do
        [ -z "$account" ] && continue
        echo "${account} | bash='/home/decoder/.config/argos/.totp-copy.sh \"${account}\"' terminal=false"
    done
fi

echo "---"
echo "Refresh | refresh=true"
