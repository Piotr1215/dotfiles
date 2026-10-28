#!/usr/bin/env bash
# Resolve an Alacritty jump hint to one live agent and switch the clicked client.
# Alacritty does not normally pass a client identity, so use the calling tty if
# it is a tmux client, otherwise the most recently active client.
set -eo pipefail

raw="${1:-}"
token="${raw#jump:}"
[ -n "$token" ] || exit 0

notice() {
  if command -v notify-send >/dev/null 2>&1; then notify-send "tmux-jump" "$1" || true; fi
}

# Mirror the cockpit's labels for the two special agent roles.
label_of() {
  if [ "$1" = task ] && [ "$2" = triage ]; then label=gordon
  elif [ "$2" = triage ]; then label="$1"
  elif [ "$2" = intake ]; then label=kendra
  else label="$2"; fi
}

mapfile -t panes < <(tmux list-panes -a \
  -F '#{session_name}|#{window_name}|#{pane_id}|#{@agent_name}' 2>/dev/null || true)
matches=()
for row in "${panes[@]}"; do
  IFS='|' read -r s wn p tag <<<"$row"
  [ -n "$tag" ] || continue
  if [[ "$token" == *:* ]]; then
    if [ "$s" != "${token%%:*}" ] || [ "$wn" != "${token#*:}" ]; then continue; fi
  else
    label_of "$s" "$tag"
    [ "$label" = "$token" ] || continue
  fi
  matches+=("$p")
done

if [ "${#matches[@]}" -eq 0 ] && [[ "$token" != *:* ]]; then
  # Exact session names take precedence over an ID delimited within a name.
  mapfile -t sessions < <(tmux list-sessions -F '#{session_name}' 2>/dev/null || true)
  for s in "${sessions[@]}"; do
    if [ "$s" = "$token" ]; then matches+=("$s"); fi
  done
  if [ "${#matches[@]}" -eq 0 ]; then
    for s in "${sessions[@]}"; do
      padded="-${s,,}-"
      normalized="${padded//[_.]/-}"
      normalized_token="${token,,}"
      normalized_token="${normalized_token//[_.]/-}"
      if [[ "$normalized" == *"-${normalized_token}-"* ]]; then matches+=("$s"); fi
    done
  fi
  # A session fallback must not silently choose between several tagged panes.
  if [ "${#matches[@]}" -eq 1 ]; then
    session="${matches[0]}"
    tagged=()
    for row in "${panes[@]}"; do
      IFS='|' read -r s wn p tag <<<"$row"
      if [ "$s" = "$session" ] && [ -n "$tag" ]; then tagged+=("$p"); fi
    done
    matches=("${tagged[@]}")
  fi
fi

if [ "${#matches[@]}" -eq 0 ]; then notice "no live agent for ${token}"; exit 0; fi
if [ "${#matches[@]}" -gt 1 ]; then notice "ambiguous target ${token}"; exit 0; fi

target="${matches[0]}"
mapfile -t clients < <(tmux list-clients -F '#{client_tty}|#{client_activity}' 2>/dev/null || true)
calling_tty="$(tty 2>/dev/null || true)"
client="" newest=-1
for row in "${clients[@]}"; do
  IFS='|' read -r client_tty activity <<<"$row"
  [ -n "$client_tty" ] || continue
  if [ "$client_tty" = "$calling_tty" ]; then client="$client_tty"; break; fi
  [[ "$activity" =~ ^[0-9]+$ ]] || continue
  if (( activity > newest )); then client="$client_tty"; newest="$activity"; fi
done
if [ -z "$client" ]; then notice "no live tmux client"; exit 0; fi

# switch-client accepts a pane ID and selects its session, window and pane.
# Repeating a hint for the current pane stays on that pane for mouse and keyboard.
if ! tmux switch-client -c "$client" -t "$target" 2>/dev/null; then
  notice "target no longer available: ${token}"
fi
