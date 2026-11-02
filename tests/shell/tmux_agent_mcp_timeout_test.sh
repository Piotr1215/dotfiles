#!/usr/bin/env bash
set -euo pipefail

config="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.config/tmuxinator/task.yml"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin" "$tmp_dir/.claude/scripts" "$tmp_dir/loft/gordon" "$tmp_dir/loft/kendra"

cat > "$tmp_dir/bin/__claude_with_monitor.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${MCP_TIMEOUT-unset}" "$PWD" "$*"
EOF
cat > "$tmp_dir/.claude/scripts/__models.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' test-model
EOF
chmod +x "$tmp_dir/bin/__claude_with_monitor.sh" "$tmp_dir/.claude/scripts/__models.sh"

# Kendra's pane runs ~/.claude/scripts/__intake_launch.sh, which picks Claude or
# Codex by load. Pin its selector to claude and its Claude launcher to the stub,
# so the line runs to the same argv without reading load or starting Claude.
printf '#!/usr/bin/env bash\nprintf "claude\\ttest\\n"\n' > "$tmp_dir/bin/selector"
chmod +x "$tmp_dir/bin/selector"
scripts="$HOME/.claude/scripts"

for window in todo kendra; do
    case "$window" in
        todo) pattern='__claude_with_monitor\.sh' ;;
        kendra) pattern='__intake_launch\.sh' ;;
    esac
    launch="$(ruby -ryaml -e '
        config = YAML.safe_load_file(ARGV.fetch(0))
        window = config.fetch("windows").find { |item| item.key?(ARGV.fetch(1)) }.fetch(ARGV.fetch(1))
        launches = window.fetch("panes").grep(Regexp.new(ARGV.fetch(2)))
        abort "expected one launcher" unless launches.size == 1
        puts launches.first
    ' "$config" "$window" "$pattern")"
    result="$(env -u MCP_TIMEOUT -u TMUX -u TMUX_PANE HOME="$tmp_dir" PATH="$tmp_dir/bin:$scripts:$PATH" \
        INTAKE_RUNTIME_SELECTOR="$tmp_dir/bin/selector" INTAKE_CLAUDE_LAUNCHER="$tmp_dir/bin/__claude_with_monitor.sh" \
        bash -c "$launch" 2>/dev/null)"
    [[ "${result%%$'\n'*}" == 120000 ]] || { printf '%s timeout missing: %s\n' "$window" "$result" >&2; exit 1; }
    case "$window" in
        todo) folder=gordon; [[ "$result" == *triage-agent-system-prompt.md* ]] ;;
        kendra) folder=kendra; [[ "$result" == *intake-agent-system-prompt.md* ]] ;;
    esac
    [[ "$(sed -n '2p' <<< "$result")" == "$tmp_dir/loft/$folder" ]] || { printf '%s cwd wrong: %s\n' "$window" "$result" >&2; exit 1; }
done
printf '%s\n' '2 launches passed: separate agent folders and MCP_TIMEOUT=120000'
