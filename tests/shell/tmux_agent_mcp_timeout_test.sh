#!/usr/bin/env bash
set -euo pipefail

config="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.config/tmuxinator/task.yml"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin" "$tmp_dir/.claude/scripts" "$tmp_dir/loft/gordon" "$tmp_dir/loft/kendra"

cat > "$tmp_dir/bin/__claude_with_monitor.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${MCP_TIMEOUT-unset}" "$PWD" "$*" "compact=${MEMORY_SEARCH_COMPACT-unset}"
EOF
cat > "$tmp_dir/.claude/scripts/__models.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' test-model
EOF
chmod +x "$tmp_dir/bin/__claude_with_monitor.sh" "$tmp_dir/.claude/scripts/__models.sh"

# Kendra is a timer function since e107f1e7 (13 Nov), so her window has no
# agent launch left to check; Gordon's todo pane is the one session launch.
launch="$(ruby -ryaml -e '
    config = YAML.safe_load_file(ARGV.fetch(0))
    window = config.fetch("windows").find { |item| item.key?("todo") }.fetch("todo")
    launches = window.fetch("panes").grep(/__claude_with_monitor\.sh/)
    abort "expected one launcher" unless launches.size == 1
    puts launches.first
' "$config")"
result="$(env -u MCP_TIMEOUT -u MEMORY_SEARCH_COMPACT -u TMUX -u TMUX_PANE HOME="$tmp_dir" \
    PATH="$tmp_dir/bin:$PATH" bash -c "$launch" 2>/dev/null)"
fail() { printf 'gordon %s: %s\n' "$1" "$result" >&2; exit 1; }
[[ "${result%%$'\n'*}" == 120000 ]] || fail "timeout missing"
[[ "$(sed -n '2p' <<< "$result")" == "$tmp_dir/loft/gordon" ]] || fail "cwd wrong"
[[ "$result" == *triage-agent-system-prompt.md* ]] || fail "system prompt missing"
# His .mcp.json is regenerated from the account on every launch (__role_home.py),
# so the compact memory-search switch must ride on the launch environment.
[[ "$result" == *"compact=1"* ]] || fail "compact memory search missing"
printf '%s\n' 'gordon launch passed: own folder, MCP_TIMEOUT=120000, triage prompt, compact memory search'
