#!/usr/bin/env bash
# Start, resume, or fork Codex with account routing derived from the working directory.
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
account_lib="$HOME/.claude/scripts/__lib_claude_account.sh"
codex_command="${CODEX_LAUNCH_BIN:-$SCRIPT_DIR/__codex_with_app_server.sh}"
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

action="${1:-}"
if [[ -z "$action" ]]; then
  action=$(printf '%s\n' new resume resume-last resume-all fork \
    | fzf --reverse --border --prompt='codex > ' \
      --preview='case {} in new) echo "Start a new Codex session";; resume) echo "Pick a session from this directory";; resume-last) echo "Resume the latest session";; resume-all) echo "Pick from every Codex session";; fork) echo "Fork an existing session";; esac')
  [[ -n "$action" ]] || exit 0
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
