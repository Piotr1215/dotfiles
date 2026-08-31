#!/usr/bin/env bash
set -eo pipefail

# Regenerate the two desktop-level binding indexes confhelp reads:
#   scripts/__autokey_bindings.conf   AutoKey hotkeys
#   scripts/__gnome_bindings.conf     GNOME custom keybindings
#
# WHY THIS EXISTS: __autokey_bindings.conf used to be typed by hand. It drifted.
# It advertised ctrl+alt+t as AutoKey's CreateTask long after that hotkey was
# disabled and GNOME took the key for a layout, it carried the window layouts as
# though AutoKey owned them, and it never gained ctrl+alt+p (SecretPicker), so
# the one shortcut Piotr went looking for was the one missing from the help.
# Both sources can be read exactly, so neither is retyped.
#
# AutoKey stores one JSON per item. A hotkey counts only when modes holds 3
# (TriggerMode.HOTKEY); an item can keep a stale hotkey record with the trigger
# switched off, and CreateTask is exactly that.
#
# GNOME keeps its custom keybindings in dconf, not in a file in this repo, so
# the generator has to run on the machine that owns them. Without gsettings the
# GNOME index is left untouched rather than emptied.

DOTFILES="${DOTFILES:-$HOME/dev/dotfiles}"
AUTOKEY_OUT="${AUTOKEY_OUT:-$DOTFILES/scripts/__autokey_bindings.conf}"
GNOME_OUT="${GNOME_OUT:-$DOTFILES/scripts/__gnome_bindings.conf}"
AUTOKEY_DATA="${AUTOKEY_DATA:-$DOTFILES/.config/autokey/data}"

# One normalizer for both sources, so a key reads the same whichever layer owns
# it. Held in a variable rather than two heredocs because the alias rule below
# has to be identical on both sides or the search stops being uniform.
read -r -d '' NORMALIZE <<'PY' || true
import glob, json, os, sys

# Reading order, so a key is written the way it is spoken.
ORDER = ["super", "ctrl", "alt", "shift"]
ALIAS = {"control": "ctrl", "primary": "ctrl", "meta": "alt", "hyper": "super"}

# Every other binding in the help is in tmux notation (M-x, C-h), and that is
# what gets typed into the search box. fzf matches a literal subsequence, so
# "m-c-h" finds nothing in "ctrl+alt+h" and the row looks missing. Carrying the
# tmux spelling alongside the canonical one makes both searches land.
TMUX = {"alt": "M", "ctrl": "C", "shift": "S", "super": "Super"}
TMUX_ORDER = ["alt", "ctrl", "shift", "super"]


def combo(mods, key):
    """Canonical key plus its tmux-notation alias, e.g. 'ctrl+alt+h (M-C-h)'."""
    mods = {ALIAS.get(m, m) for m in (m.strip("<>").lower() for m in mods)}
    key = key.strip("<>")
    canonical = "+".join([m for m in ORDER if m in mods] + [key.lower()])
    if not mods:
        return canonical
    tmux = "-".join([TMUX[m] for m in TMUX_ORDER if m in mods] + [key])
    return f"{canonical} ({tmux})"


def autokey(data):
    rows = []
    for path in glob.glob(os.path.join(data, "**", ".*.json"), recursive=True):
        try:
            item = json.load(open(path))
        except (OSError, ValueError):
            continue
        hotkey = item.get("hotkey") or {}
        key = hotkey.get("hotKey")
        # 3 is TriggerMode.HOTKEY. Anything else means the record is dormant.
        if not key or 3 not in (item.get("modes") or []):
            continue

        # The item's own script or phrase, so the help jumps to what the key
        # runs rather than to this generated line.
        stem = os.path.join(os.path.dirname(path), os.path.basename(path)[1:-5])
        target = next((stem + e for e in (".py", ".txt") if os.path.exists(stem + e)), "")
        # A folder record has no script of its own; its hotkey opens the tray
        # menu for the folder, and only "title" names it.
        desc = item.get("description") or item.get("title") or os.path.basename(stem)
        if item.get("type") == "folder":
            desc = f"{desc} (folder menu)"
        rows.append((combo(hotkey.get("modifiers", []), key), f"{desc}  {target}".rstrip()))
    return rows


def gnome(lines):
    """Read '<Primary><Alt>a|name|command' triples from gsettings, on stdin."""
    rows = []
    for line in lines:
        raw, _, rest = line.rstrip("\n").partition("|")
        name, _, command = rest.partition("|")
        if not raw:
            continue
        mods = [m.strip("<>") for m in raw.split(">") if m.startswith("<")]
        # Modifiers are all leading, so everything past the last '>' is the key.
        # A bare key such as Print has no '>' and comes through untouched.
        rows.append((combo(mods, raw.split(">")[-1]), f"{name}  {command}".rstrip()))
    return rows


rows = autokey(sys.argv[2]) if sys.argv[1] == "autokey" else gnome(sys.stdin)
for key, desc in sorted(rows):
    print(f"{key}|{desc}")
PY

gnome_records() {
    local schema="org.gnome.settings-daemon.plugins.media-keys"
    local path binding name command
    while read -r path; do
        [ -n "$path" ] || continue
        binding=$(gsettings get "${schema}.custom-keybinding:${path}" binding 2>/dev/null | sed "s/^'//; s/'$//")
        [ -n "$binding" ] || continue
        name=$(gsettings get "${schema}.custom-keybinding:${path}" name 2>/dev/null | sed "s/^'//; s/'$//")
        command=$(gsettings get "${schema}.custom-keybinding:${path}" command 2>/dev/null | sed "s/^'//; s/'$//")
        printf '%s|%s|%s\n' "$binding" "$name" "$command"
    done < <(gsettings get "$schema" custom-keybindings 2>/dev/null | tr -d "[]'," | tr ' ' '\n')
}

header() {
    printf '# Generated by __desktop_bindings_gen.sh. Do not edit; rerun the generator.\n'
    printf '# %s\n' "$1"
}

{
    header '<key> (tmux notation)|<name>  <script it runs>'
    python3 -c "$NORMALIZE" autokey "$AUTOKEY_DATA"
} > "$AUTOKEY_OUT"

if command -v gsettings >/dev/null 2>&1; then
    {
        header '<key> (tmux notation)|<name>  <command>'
        gnome_records | python3 -c "$NORMALIZE" gnome
    } > "$GNOME_OUT"
else
    echo "gsettings not found; left $GNOME_OUT untouched" >&2
fi
