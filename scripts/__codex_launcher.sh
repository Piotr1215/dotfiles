#!/usr/bin/env bash
# Start, resume, or fork Codex with account routing derived from the working directory.
set -eo pipefail

account_lib="$HOME/.claude/scripts/__lib_claude_account.sh"
codex_command="${CODEX_LAUNCH_BIN:-$HOME/.codex/scripts/__codex_with_app_server.sh}"
fallback_cwd="${CODEX_LAUNCH_CWD:-}"
launch_cwd="$fallback_cwd"

if [[ "${1:-}" == "--cwd" ]]; then
  requested_cwd="${2:?--cwd requires a directory}"
  case "$requested_cwd" in
    '#{'*'}') launch_cwd="$fallback_cwd" ;;
    *) launch_cwd="$requested_cwd" ;;
  esac
  shift 2
fi

[[ -n "$launch_cwd" ]] || launch_cwd=$PWD

action="${1:-}"
if [[ -z "$action" ]]; then
  picker_result=$(
    {
      printf '%s\n' "$launch_cwd"
      zoxide query -l 2>/dev/null
    } | awk 'NF && !seen[$0]++' | fzf \
      --reverse --border --tiebreak=index \
      --prompt='codex> ' \
      --header='enter:new  ctrl-r:resume  ctrl-l:resume-last  ctrl-a:resume-all  ctrl-f:fork' \
      --expect=ctrl-r,ctrl-l,ctrl-a,ctrl-f \
      --preview='eza --color=always --icons --git {} 2>/dev/null' \
      --preview-window=right:50%:wrap
  ) || exit 0

  picker_key=$(head -1 <<< "$picker_result")
  launch_cwd=$(tail -1 <<< "$picker_result")
  [[ -n "$launch_cwd" ]] || exit 0

  case "$picker_key" in
    ctrl-r) action=resume ;;
    ctrl-l) action=resume-last ;;
    ctrl-a) action=resume-all ;;
    ctrl-f) action=fork ;;
    *) action=new ;;
  esac
fi

[[ -d "$launch_cwd" ]] || {
  echo "error: launch directory does not exist: $launch_cwd" >&2
  exit 1
}
launch_cwd=$(cd "$launch_cwd" && pwd)

# Popups have no TMUX_PANE of their own. Preserve the pane that opened the
# launcher so the Codex wrapper can bind its app-server to that pane's kctx
# runtime rather than falling back to one global process environment.
if [[ -n "${TMUX:-}" ]]; then
  CODEX_TMUX_PANE=$(tmux display-message -p '#{pane_id}' 2>/dev/null || true)
  export CODEX_TMUX_PANE
fi

# shellcheck source=/dev/null
source "$account_lib" 2>/dev/null || claude_work_predicate() { return 1; }
if [[ -d "$HOME/.codex-work" ]] && claude_work_predicate "$launch_cwd"; then
  export CODEX_HOME="$HOME/.codex-work"
  active_codex_home=$CODEX_HOME
else
  unset CODEX_HOME
  active_codex_home="$HOME/.codex"
fi

case "$action" in
  new|resume|resume-last|resume-all|fork) ;;
  *)
    echo "error: unknown Codex launcher action: $action" >&2
    exit 1
    ;;
esac

if [[ "${CODEX_LAUNCH_DRY_RUN:-0}" == "1" ]]; then
  jq -n --arg action "$action" --arg cwd "$launch_cwd" --arg codex_home "$active_codex_home" '{
    action: $action,
    cwd: $cwd,
    codex_home: $codex_home
  }'
  exit 0
fi

cd "$launch_cwd"
case "$action" in
  new) exec "$codex_command" ;;
  resume) exec "$codex_command" resume ;;
  resume-last) exec "$codex_command" resume --last ;;
  resume-all) exec "$codex_command" resume --all ;;
  fork) exec "$codex_command" fork ;;
esac
