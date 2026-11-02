#!/usr/bin/env bash
set -euo pipefail

config="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.config/tmuxinator/task.yml"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin" "$tmp_dir/.claude/scripts"

cat > "$tmp_dir/bin/__claude_with_monitor.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${MCP_TIMEOUT-unset}" "$*"
EOF
cat > "$tmp_dir/.claude/scripts/__models.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' test-model
EOF
chmod +x "$tmp_dir/bin/__claude_with_monitor.sh" "$tmp_dir/.claude/scripts/__models.sh"

for window in todo kendra; do
    launch="$(ruby -ryaml -e '
        config = YAML.safe_load_file(ARGV.fetch(0))
        window = config.fetch("windows").find { |item| item.key?(ARGV.fetch(1)) }.fetch(ARGV.fetch(1))
        launches = window.fetch("panes").grep(/__claude_with_monitor\.sh/)
        abort "expected one launcher" unless launches.size == 1
        puts launches.first
    ' "$config" "$window")"
    result="$(env -u MCP_TIMEOUT HOME="$tmp_dir" PATH="$tmp_dir/bin:$PATH" bash -c "$launch")"
    [[ "${result%%$'\n'*}" == 120000 ]] || { printf '%s timeout missing: %s\n' "$window" "$result" >&2; exit 1; }
    case "$window" in
        todo) [[ "$result" == *triage-agent-system-prompt.md* ]] ;;
        kendra) [[ "$result" == *intake-agent-system-prompt.md* ]] ;;
    esac
done
printf '%s\n' 'Gordon and Kendra launch with MCP_TIMEOUT=120000'
