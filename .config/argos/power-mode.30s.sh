#!/usr/bin/env bash
# PROJECT: graphics-mode-aliases
#
# Argos panel: invisible on AC, visible on battery.
# When on battery, surfaces a switch action toward `speak` (hybrid + battery)
# and shows live draw/runtime so the user can spot mismatches at a glance.
#
# Refresh: 30s (from filename suffix). Argos hides the panel item if stdout
# is empty, so an early `exit 0` while AC is connected keeps the panel clean.

set -eo pipefail

# --- AC gate --------------------------------------------------------------
ac_online_file="/sys/class/power_supply/AC/online"
if [[ -r "$ac_online_file" ]]; then
  ac="$(<"$ac_online_file")"
else
  ac="0"
fi
if [[ "$ac" == "1" ]]; then
  # Argos renders the filename when stdout is empty. Emit a zero-width
  # Pango span so argos sees output but the panel renders nothing visible.
  echo "<span size='1'> </span> | dropdown=false"
  exit 0
fi

# --- gather state ---------------------------------------------------------
graphics="$(system76-power graphics 2>/dev/null || echo unknown)"
profile_line="$(system76-power profile 2>/dev/null | head -n1 || true)"
profile="${profile_line#Power Profile: }"
profile="${profile,,}"  # lowercase

bat="$(upower -i "$(upower -e | grep -m1 BAT)" 2>/dev/null || true)"
percent="$(awk -F: '/percentage:/ {gsub(/ /,"",$2); print $2}' <<<"$bat")"
draw="$(awk -F: '/energy-rate:/ {gsub(/ |W/,"",$2); print $2}' <<<"$bat")"
energy="$(awk -F: '/energy:/ && !/full|rate|design/ {gsub(/ |Wh/,"",$2); print $2}' <<<"$bat")"
ttempty="$(awk -F: '/time to empty:/ {sub(/^ */,"",$2); print $2}' <<<"$bat")"
[[ -z "$ttempty" ]] && ttempty="—"
[[ -z "$percent" ]] && percent="?"
[[ -z "$draw" ]]    && draw="?"
[[ -z "$energy" ]]  && energy="?"

# --- mismatch evaluation --------------------------------------------------
# On battery the ideal is `speak` mode: hybrid graphics + battery profile.
# Anything else is a chance to save power.
status="ok"
status_text="speak"
if [[ "$graphics" != "hybrid" ]]; then
  status="mismatch"
  status_text="${graphics} on battery — switch to speak"
elif [[ "$profile" != "battery" ]]; then
  status="profile"
  status_text="hybrid + ${profile} — flip profile to battery"
fi

case "$status" in
  ok)        color="#44ff44"; icon="🔋" ;;
  profile)   color="#ffcc00"; icon="⚠"  ;;
  mismatch)  color="#ff4444"; icon="🔥" ;;
esac

draw_fmt="$(printf "%.1fW" "${draw:-0}")"
energy_fmt="$(printf "%.0fWh" "${energy:-0}")"
# Compact time format: "1.8 hours" -> "1.8h", "45 minutes" -> "45m"
ttempty_short="${ttempty/ hours/h}"
ttempty_short="${ttempty_short/ hour/h}"
ttempty_short="${ttempty_short/ minutes/m}"
ttempty_short="${ttempty_short/ minute/m}"

# Graphics-mode tag — makes the upower estimate's fragility legible:
# nvidia idles cheap but spikes hard under load.
case "$graphics" in
  nvidia)     gfx_tag="N" ;;
  hybrid)     gfx_tag="H" ;;
  integrated) gfx_tag="I" ;;
  compute)    gfx_tag="C" ;;
  *)          gfx_tag="?" ;;
esac

# --- panel line (% omitted — GNOME shows it natively) ---------------------
# Layout: [icon] [N|H|I] [draw]W [Wh remaining] @ [time] — Wh lets you do
# your own worst-case math; the @time is upower's instantaneous projection.
echo "<span color='${color}'>${icon} ${gfx_tag} ${draw_fmt} ${energy_fmt} @${ttempty_short}</span> | font='monospace' size=11"
echo "---"
echo "<b>Power state</b> (battery) | font=monospace"
echo "AC: disconnected"
echo "Graphics: ${graphics}"
echo "Profile : ${profile}"
echo "Battery : ${percent} | draw ${draw_fmt} | ${ttempty}"
echo "Status  : ${status_text}"
echo "---"
echo "<b>Switch mode</b> (will reboot)"
echo "🎤 speak — hybrid + battery | bash='__set_graphics_mode.sh speak' terminal=true"
echo "🏠 base  — nvidia + balanced | bash='__set_graphics_mode.sh base' terminal=true"
echo "---"
echo "<b>Profile only</b> (no reboot)"
echo "⚡ battery     | bash='system76-power profile battery'     terminal=false refresh=true"
echo "⚖ balanced    | bash='system76-power profile balanced'    terminal=false refresh=true"
echo "🚀 performance | bash='system76-power profile performance' terminal=false refresh=true"
echo "---"
echo "Refresh now | refresh=true"
