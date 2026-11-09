#!/usr/bin/env bash
# Run full configured Neovim while shared brief generation is paused.
set -eo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
file=${1:?brief path required}
nvim_bin=${HANDOFF_NVIM_COMMAND:-nvim}
state=${XDG_STATE_HOME:-$HOME/.local/state}
brief_root="$state/taskwarrior/briefs"
lock="$brief_root/.editor.lock"
save_script=${HANDOFF_SAVE_SCRIPT:-$root/__handoff_brief_save.py}
brief_tool=${HANDOFF_RECONCILE_COMMAND:-$HOME/.claude/scripts/__tw_brief.py}
mkdir -p "$brief_root"
chmod 700 "$brief_root"

exec 3>&2
exec 2> >(while IFS= read -r line; do
  printf '%s uuid=%s mode=editor %s\n' "$(date -Is)" "$HANDOFF_UUID" "$line" \
    | tee -a "$state/handoff-floater.log" >&3
done)

# When the brief closes while it holds focus, hand focus back to the task view.
# Only the floater sets HANDOFF_RETURN_FOCUS, so a run outside its pane never
# selects a pane on some other tmux server.
return_focus() {
  local tmux_bin=${HANDOFF_TMUX_COMMAND:-tmux}
  [[ "${HANDOFF_RETURN_FOCUS:-}" == 1 && "${TMUX_PANE:-}" =~ ^%[0-9]+$ \
    && "${HANDOFF_ORIGIN:-}" =~ ^%[0-9]+$ ]] || return 0
  [[ $("$tmux_bin" display-message -p -t "$TMUX_PANE" '#{pane_active}' 2>/dev/null) == 1 ]] || return 0
  "$tmux_bin" select-pane -t "$HANDOFF_ORIGIN" 2>/dev/null || true
}
trap return_focus EXIT

exec 9>"$lock"
flock -sn 9 || { echo 'Another handoff brief editor is already open.' >&2; exit 1; }
python3 "$save_script" init "$HANDOFF_UUID"
# This shell holds the lock for the whole edit. Neovim gets fd 9 closed: its
# children (the xsel clipboard owner) outlive it and would keep the lock after
# the exec below, so parked brief updates waited on a closed editor.
"$nvim_bin" --listen "$XDG_RUNTIME_DIR/taskwarrior-tui/handoff-${HANDOFF_ORIGIN#%}.sock" \
  -c 'lua dofile(vim.env.HANDOFF_ROOT .. "/__handoff_floater_v2.lua")' -- "$file" 9>&-
exec 9>&-
python3 "$brief_tool" --reconcile-pending >/dev/null
python3 "$root/__handoff_floater_file.py" --refresh-pending >/dev/null
